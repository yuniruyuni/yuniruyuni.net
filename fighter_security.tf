# =============================================================================
# Fighter Notes security boundary
# =============================================================================
#
# This file intentionally adds the dedicated identities before removing the
# legacy default-service-account grants in gcp.tf. The cutover order is:
# create -> verify -> switch workloads -> observe -> remove legacy grants.

data "google_project" "current" {
  project_id = var.gcp_project_id
}

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

  legacy_default_compute_service_account = "${data.google_project.current.number}-compute@developer.gserviceaccount.com"
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

resource "google_project_iam_audit_config" "fighter_identity_services" {
  for_each = toset([
    "iam.googleapis.com",
    "sts.googleapis.com",
  ])

  project = var.gcp_project_id
  service = each.value

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

  depends_on = [
    google_project_service.required,
    google_project_iam_member.terraform_github["roles/logging.configWriter"],
  ]
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
      protoPayload.serviceName="run.googleapis.com" OR
      protoPayload.serviceName="cloudscheduler.googleapis.com"
    )
  EOT
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

# Cloud Scheduler needs a Google service account only to mint the OAuth token
# used for Jobs.run. It cannot update the Job and receives no workload secrets.
resource "google_service_account" "fighter_cleanup_scheduler" {
  account_id   = "fighter-cleanup-scheduler"
  display_name = "Fighter Notes Cleanup Scheduler"
  description  = "Invokes only the Fighter Notes expiry cleanup Cloud Run Job"
}

# Terraform owns the cleanup Job's existence so resource-level IAM can be
# attached before the first application deployment. fighter-notes owns the
# executable template and replaces it on every release; ignoring template
# drift avoids duplicating that application configuration in this repository.
resource "google_cloud_run_v2_job" "fighter_cleanup_bootstrap" {
  project             = var.gcp_project_id
  location            = var.gcp_region
  name                = "fighter-cleanup"
  deletion_protection = true

  template {
    template {
      service_account = google_service_account.fighter_workload["cleanup"].email
      max_retries     = 0
      timeout         = "60s"

      containers {
        name  = "bootstrap"
        image = "us-docker.pkg.dev/cloudrun/container/job@sha256:607a768501c02c101d852c250ffa8b18021ddd9e0ec9215ed2763494f66de5e4"
      }
    }
  }

  lifecycle {
    ignore_changes = [template, client, client_version]
  }

  depends_on = [
    google_project_service.required["run.googleapis.com"],
    google_service_account_iam_member.terraform_github_fighter_cleanup_act_as,
  ]
}

resource "google_cloud_run_v2_job_iam_member" "fighter_cleanup_scheduler_invoker" {
  project  = var.gcp_project_id
  location = var.gcp_region
  name     = google_cloud_run_v2_job.fighter_cleanup_bootstrap.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.fighter_cleanup_scheduler.email}"
}

# The CI apply identity needs actAs only to bootstrap the Job with its dedicated
# workload identity. It does not receive any of that identity's secret access.
resource "google_service_account_iam_member" "terraform_github_fighter_cleanup_act_as" {
  service_account_id = google_service_account.fighter_workload["cleanup"].name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.terraform_github.email}"
}

# The CI apply identity must be able to attach the OAuth identity to the
# Scheduler target. This does not grant it access to that identity's tokens.
resource "google_service_account_iam_member" "terraform_github_fighter_cleanup_scheduler_act_as" {
  service_account_id = google_service_account.fighter_cleanup_scheduler.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.terraform_github.email}"
}

resource "google_cloud_scheduler_job" "fighter_cleanup" {
  project          = var.gcp_project_id
  region           = var.gcp_region
  name             = "fighter-cleanup-daily"
  description      = "Run the Fighter Notes expiry cleanup Cloud Run Job every day"
  schedule         = "23 2 * * *"
  time_zone        = "Asia/Tokyo"
  attempt_deadline = "30s"

  retry_config {
    retry_count          = 3
    max_retry_duration   = "600s"
    min_backoff_duration = "5s"
    max_backoff_duration = "60s"
    max_doublings        = 3
  }

  http_target {
    http_method = "POST"
    uri         = "https://run.googleapis.com/v2/projects/${var.gcp_project_id}/locations/${var.gcp_region}/jobs/fighter-cleanup:run"
    body        = base64encode("{}")

    headers = {
      "Content-Type" = "application/json"
    }

    oauth_token {
      service_account_email = google_service_account.fighter_cleanup_scheduler.email
    }
  }

  depends_on = [
    google_project_service.required["cloudscheduler.googleapis.com"],
    google_cloud_run_v2_job_iam_member.fighter_cleanup_scheduler_invoker,
    google_service_account_iam_member.terraform_github_fighter_cleanup_scheduler_act_as,
  ]
}

resource "cloudflare_zero_trust_access_service_token" "fighter_db" {
  for_each = local.fighter_workloads

  account_id = var.cloudflare_account_id
  name       = "Fighter Notes ${title(each.key)} DB Access"
}

# Cloudflare returns each client_secret only at creation, so its resource state
# is credential-sensitive. The protected Terraform backend and manually
# approved plan Environment are part of this trust boundary. Secret Manager
# versions below use write-only arguments to avoid duplicating token material
# in their own resource state.

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

  secret                 = google_secret_manager_secret.fighter_cf_db_client_id[each.key].id
  secret_data_wo         = cloudflare_zero_trust_access_service_token.fighter_db[each.key].client_id
  secret_data_wo_version = 1
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

  secret                 = google_secret_manager_secret.fighter_cf_db_client_secret[each.key].id
  secret_data_wo         = cloudflare_zero_trust_access_service_token.fighter_db[each.key].client_secret
  secret_data_wo_version = 1
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

# Runtime and cleanup share the DML credential. Migration alone receives the
# owner/DDL credential. GCP service accounts and Cloudflare tokens remain
# isolated per workload.
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

resource "google_secret_manager_secret_iam_member" "fighter_cleanup_db" {
  secret_id = google_secret_manager_secret.db_app_password["fighter"].id
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

  # Automatic scans are billed per image digest, so keep them disabled for this
  # personal project even if scanning is enabled outside Terraform.
  vulnerability_scanning_config {
    enablement_config = "DISABLED"
  }

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
    assertion.workflow_ref == "${local.fighter_github.repository}/.github/workflows/deploy.yml@refs/heads/main"
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
    assertion.workflow_ref == "${local.fighter_github.repository}/.github/workflows/deploy.yml@refs/heads/main"
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

# The deployer may inspect immutable manifests and attestations, but cannot
# upload, retag, or delete artifacts.
resource "google_artifact_registry_repository_iam_member" "fighter_deployer_reader" {
  project    = var.gcp_project_id
  location   = google_artifact_registry_repository.fighter.location
  repository = google_artifact_registry_repository.fighter.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.fighter_deployer.email}"
}

# The project currently has no organization parent. Google only allows the
# Deny Admin and Deny Reviewer roles to be granted at organization level, so a
# project-level deny policy cannot be bootstrapped here. Until the remaining
# workloads migrate away from the legacy default Compute SA and its Editor role
# is removed, that identity can still upload to repositories where Editor is
# sufficient. Fighter mitigates this residual risk with a dedicated immutable
# repository, unique release tags, and separate builder/deployer identities.

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

resource "google_cloud_run_v2_job_iam_member" "fighter_cleanup_deployer" {
  project  = var.gcp_project_id
  location = var.gcp_region
  name     = google_cloud_run_v2_job.fighter_cleanup_bootstrap.name
  role     = "roles/run.developer"
  member   = "serviceAccount:${google_service_account.fighter_deployer.email}"
}

resource "google_service_account_iam_member" "fighter_deployer_act_as" {
  for_each = local.fighter_workloads

  service_account_id = google_service_account.fighter_workload[each.key].name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.fighter_deployer.email}"
}
