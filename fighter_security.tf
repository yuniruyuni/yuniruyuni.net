# =============================================================================
# Fighter Notes security boundary
# =============================================================================
#
# This file intentionally adds the dedicated identities before removing the
# legacy default-service-account grants in gcp.tf. The cutover order is:
# create -> verify -> switch workloads -> observe -> remove legacy grants.

locals {
  fighter_github = {
    owner_id      = "85034901"
    repository_id = "1292768512"
    repository    = "yuniruyuni/fighter-notes"
  }

  fighter_workloads = {
    runtime = {
      account_id   = "fighter-runtime"
      display_name = "Fighter Notes Runtime"
    }
    migration = {
      account_id   = "fighter-migration"
      display_name = "Fighter Notes Migration"
    }
    cleanup = {
      account_id   = "fighter-cleanup"
      display_name = "Fighter Notes Expiry Cleanup"
    }
  }
}

# -----------------------------------------------------------------------------
# Secret Manager audit trail
# -----------------------------------------------------------------------------

resource "google_project_iam_audit_config" "secret_manager" {
  project = var.gcp_project_id
  service = "secretmanager.googleapis.com"

  audit_log_config {
    log_type = "DATA_READ"
  }

  audit_log_config {
    log_type = "ADMIN_READ"
  }
}

resource "google_logging_project_bucket_config" "fighter_security" {
  project        = var.gcp_project_id
  location       = "global"
  bucket_id      = "fighter-security"
  retention_days = 90
  description    = "Protected audit trail for Fighter Notes identity and secret access"

  depends_on = [google_project_service.required]
}

resource "google_logging_project_sink" "fighter_security" {
  name        = "fighter-security-audit"
  project     = var.gcp_project_id
  destination = "logging.googleapis.com/${google_logging_project_bucket_config.fighter_security.id}"
  filter      = <<-EOT
    logName:"cloudaudit.googleapis.com" AND (
      protoPayload.serviceName="secretmanager.googleapis.com" OR
      protoPayload.serviceName="iam.googleapis.com" OR
      protoPayload.serviceName="iamcredentials.googleapis.com" OR
      protoPayload.serviceName="sts.googleapis.com" OR
      protoPayload.serviceName="run.googleapis.com"
    )
  EOT
}

resource "google_logging_metric" "fighter_default_sa_secret_read" {
  name        = "fighter_default_sa_secret_read"
  description = "Secret Manager reads performed by the legacy Compute Engine default SA"
  project     = var.gcp_project_id
  filter      = <<-EOT
    log_id("cloudaudit.googleapis.com/data_access")
    protoPayload.serviceName="secretmanager.googleapis.com"
    protoPayload.authenticationInfo.principalEmail="249322615782-compute@developer.gserviceaccount.com"
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

resource "google_monitoring_alert_policy" "fighter_default_sa_secret_read" {
  project      = var.gcp_project_id
  display_name = "Fighter: default SA accessed Secret Manager"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "Any legacy default-SA secret read"
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.fighter_default_sa_secret_read.name}\" AND resource.type=\"audited_resource\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }

  documentation {
    content   = "Investigate the caller and workload. Fighter workloads must use dedicated service accounts. Never log secret payloads."
    mime_type = "text/markdown"
  }

  depends_on = [google_project_service.required]
}

# -----------------------------------------------------------------------------
# Dedicated workload identities and per-workload Cloudflare DB credentials
# -----------------------------------------------------------------------------

resource "google_service_account" "fighter_workload" {
  for_each = local.fighter_workloads

  account_id   = each.value.account_id
  display_name = each.value.display_name
  description  = "Least-privilege identity for ${each.key} of Fighter Notes"
}

resource "cloudflare_zero_trust_access_service_token" "fighter_db" {
  for_each = local.fighter_workloads

  account_id = var.cloudflare_account_id
  name       = "Fighter Notes ${title(each.key)} DB Access"
}

resource "cloudflare_zero_trust_access_policy" "fighter_db" {
  account_id = var.cloudflare_account_id
  name       = "Fighter Notes DB Service Tokens"
  decision   = "non_identity"

  include = [for token in cloudflare_zero_trust_access_service_token.fighter_db : {
    service_token = {
      token_id = token.id
    }
  }]
}

resource "google_secret_manager_secret" "fighter_cf_db_client_id" {
  for_each = local.fighter_workloads

  secret_id = "fighter-${each.key}-cf-db-access-client-id"
  replication {
    auto {}
  }
  depends_on = [google_project_service.required]
}

resource "google_secret_manager_secret_version" "fighter_cf_db_client_id" {
  for_each = local.fighter_workloads

  secret      = google_secret_manager_secret.fighter_cf_db_client_id[each.key].id
  secret_data = cloudflare_zero_trust_access_service_token.fighter_db[each.key].client_id
}

resource "google_secret_manager_secret" "fighter_cf_db_client_secret" {
  for_each = local.fighter_workloads

  secret_id = "fighter-${each.key}-cf-db-access-client-secret"
  replication {
    auto {}
  }
  depends_on = [google_project_service.required]
}

resource "google_secret_manager_secret_version" "fighter_cf_db_client_secret" {
  for_each = local.fighter_workloads

  secret      = google_secret_manager_secret.fighter_cf_db_client_secret[each.key].id
  secret_data = cloudflare_zero_trust_access_service_token.fighter_db[each.key].client_secret
}

resource "google_secret_manager_secret_iam_member" "fighter_cf_db_client_id" {
  for_each = local.fighter_workloads

  secret_id = google_secret_manager_secret.fighter_cf_db_client_id[each.key].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.fighter_workload[each.key].email}"
}

resource "google_secret_manager_secret_iam_member" "fighter_cf_db_client_secret" {
  for_each = local.fighter_workloads

  secret_id = google_secret_manager_secret.fighter_cf_db_client_secret[each.key].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.fighter_workload[each.key].email}"
}

# Runtime gets only the DML credential. Migration gets only the owner/DDL
# credential. Cleanup receives a separate DB credential in the cleanup phase.
resource "google_secret_manager_secret_iam_member" "fighter_runtime_db" {
  secret_id = google_secret_manager_secret.db_app_password["fighter"].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.fighter_workload["runtime"].email}"
}

resource "google_secret_manager_secret_iam_member" "fighter_migration_db" {
  secret_id = google_secret_manager_secret.db_password["fighter"].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.fighter_workload["migration"].email}"
}

# The password value is inserted manually and mirrored only as an age-encrypted
# NixOS secret. The import block adopts the pre-created Secret without exposing
# its version payload to Terraform state.
resource "google_secret_manager_secret" "fighter_cleanup_db" {
  secret_id = "fighter-db-cleanup-password"
  labels = {
    app     = "fighter"
    purpose = "cleanup"
  }
  replication {
    auto {}
  }
  depends_on = [google_project_service.required]
}

import {
  to = google_secret_manager_secret.fighter_cleanup_db
  id = "projects/yuniruyuni-net/secrets/fighter-db-cleanup-password"
}

resource "google_secret_manager_secret_iam_member" "fighter_cleanup_db" {
  secret_id = google_secret_manager_secret.fighter_cleanup_db.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.fighter_workload["cleanup"].email}"
}

# -----------------------------------------------------------------------------
# Fighter-only Artifact Registry and GitHub federation
# -----------------------------------------------------------------------------

resource "google_artifact_registry_repository" "fighter" {
  location      = var.gcp_region
  repository_id = "fighter"
  description   = "Immutable production images for Fighter Notes"
  format        = "DOCKER"

  docker_config {
    immutable_tags = true
  }

  cleanup_policies {
    id     = "keep-recent-versions"
    action = "KEEP"
    most_recent_versions {
      keep_count = 10
    }
  }

  cleanup_policies {
    id     = "delete-old-untagged-images"
    action = "DELETE"
    condition {
      tag_state  = "UNTAGGED"
      older_than = "2592000s"
    }
  }

  depends_on = [google_project_service.required]
}

resource "google_service_account" "fighter_builder" {
  account_id   = "fighter-notes-builder"
  display_name = "Fighter Notes Image Builder"
  description  = "Pushes immutable Fighter Notes images; cannot deploy workloads"
}

resource "google_service_account" "fighter_deployer" {
  account_id   = "fighter-notes-deployer"
  display_name = "Fighter Notes Production Deployer"
  description  = "Updates only Fighter Notes Cloud Run resources; cannot push images or read secrets"
}

resource "google_iam_workload_identity_pool" "fighter_github" {
  workload_identity_pool_id = "fighter-notes-pool"
  display_name              = "Fighter Notes GitHub Actions"
  description               = "Repository-ID-bound identities for Fighter Notes build and production release"
}

resource "google_iam_workload_identity_pool_provider" "fighter_builder" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.fighter_github.workload_identity_pool_id
  workload_identity_pool_provider_id = "builder"
  display_name                       = "Fighter Notes Builder"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.pipeline"   = "'builder'"
    "attribute.repository" = "assertion.repository_id"
  }

  attribute_condition = <<-EOT
    assertion.repository_owner_id == "${local.fighter_github.owner_id}" &&
    assertion.repository_id == "${local.fighter_github.repository_id}" &&
    assertion.ref == "refs/heads/main" &&
    assertion.job_workflow_ref == "${local.fighter_github.repository}/.github/workflows/build-image.yml@refs/heads/main" &&
    assertion.workflow_ref in [
      "${local.fighter_github.repository}/.github/workflows/deploy.yml@refs/heads/main",
      "${local.fighter_github.repository}/.github/workflows/migrate.yml@refs/heads/main",
      "${local.fighter_github.repository}/.github/workflows/cleanup.yml@refs/heads/main"
    ]
  EOT

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_iam_workload_identity_pool_provider" "fighter_deployer" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.fighter_github.workload_identity_pool_id
  workload_identity_pool_provider_id = "deployer"
  display_name                       = "Fighter Notes Deployer"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.pipeline"   = "'deployer'"
    "attribute.repository" = "assertion.repository_id"
  }

  attribute_condition = <<-EOT
    assertion.repository_owner_id == "${local.fighter_github.owner_id}" &&
    assertion.repository_id == "${local.fighter_github.repository_id}" &&
    assertion.ref == "refs/heads/main" &&
    assertion.sub == "repo:${local.fighter_github.repository}:environment:production" &&
    assertion.workflow_ref in [
      "${local.fighter_github.repository}/.github/workflows/deploy.yml@refs/heads/main",
      "${local.fighter_github.repository}/.github/workflows/migrate.yml@refs/heads/main"
    ]
  EOT

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account_iam_member" "fighter_builder_wif" {
  service_account_id = google_service_account.fighter_builder.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.fighter_github.name}/attribute.pipeline/builder"
}

resource "google_service_account_iam_member" "fighter_deployer_wif" {
  service_account_id = google_service_account.fighter_deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.fighter_github.name}/attribute.pipeline/deployer"
}

resource "google_artifact_registry_repository_iam_member" "fighter_builder" {
  project    = var.gcp_project_id
  location   = google_artifact_registry_repository.fighter.location
  repository = google_artifact_registry_repository.fighter.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.fighter_builder.email}"
}

resource "google_cloud_run_service_iam_member" "fighter_deployer" {
  project  = var.gcp_project_id
  location = var.gcp_region
  service  = local.cloud_run_services.fighter.name
  role     = "roles/run.developer"
  member   = "serviceAccount:${google_service_account.fighter_deployer.email}"
}

resource "google_cloud_run_v2_job_iam_member" "fighter_migration_deployer" {
  project  = var.gcp_project_id
  location = var.gcp_region
  name     = "fighter-migration"
  role     = "roles/run.developer"
  member   = "serviceAccount:${google_service_account.fighter_deployer.email}"
}

# A project-level binding is needed only for the first creation of the cleanup
# Job. The IAM condition prevents the deployer from creating or changing any
# other Cloud Run resource.
resource "google_project_iam_member" "fighter_cleanup_deployer" {
  project = var.gcp_project_id
  role    = "roles/run.developer"
  member  = "serviceAccount:${google_service_account.fighter_deployer.email}"

  condition {
    title       = "fighter_cleanup_job_only"
    description = "Allow create/update/execute only for the Fighter cleanup Job"
    expression  = "resource.type == 'run.googleapis.com/Job' && resource.name.endsWith('/jobs/fighter-cleanup')"
  }
}

resource "google_service_account_iam_member" "fighter_deployer_act_as" {
  for_each = local.fighter_workloads

  service_account_id = google_service_account.fighter_workload[each.key].name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.fighter_deployer.email}"
}
