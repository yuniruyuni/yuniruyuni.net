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

  fighter_default_compute_service_account = "${data.google_project.current.number}-compute@developer.gserviceaccount.com"
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
    "iamcredentials.googleapis.com",
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
      protoPayload.serviceName="run.googleapis.com" OR
      protoPayload.serviceName="cloudscheduler.googleapis.com"
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
    protoPayload.authenticationInfo.principalEmail="${local.fighter_default_compute_service_account}"
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

resource "google_logging_metric" "fighter_unexpected_secret_read" {
  name        = "fighter_unexpected_secret_read"
  description = "Secret reads by Fighter identities outside their per-workload allowlist"
  project     = var.gcp_project_id
  filter      = <<-EOT
    log_id("cloudaudit.googleapis.com/data_access")
    protoPayload.serviceName="secretmanager.googleapis.com"
    protoPayload.methodName="google.cloud.secretmanager.v1.SecretManagerService.AccessSecretVersion"
    (
      (
        protoPayload.authenticationInfo.principalEmail="fighter-runtime@${var.gcp_project_id}.iam.gserviceaccount.com" AND NOT (
          protoPayload.resourceName:"/secrets/fighter-db-app-password/versions/" OR
          protoPayload.resourceName:"/secrets/fighter-runtime-cf-db-access-client-id/versions/" OR
          protoPayload.resourceName:"/secrets/fighter-runtime-cf-db-access-client-secret/versions/"
        )
      ) OR
      (
        protoPayload.authenticationInfo.principalEmail="fighter-migration@${var.gcp_project_id}.iam.gserviceaccount.com" AND NOT (
          protoPayload.resourceName:"/secrets/fighter-db-password/versions/" OR
          protoPayload.resourceName:"/secrets/fighter-migration-cf-db-access-client-id/versions/" OR
          protoPayload.resourceName:"/secrets/fighter-migration-cf-db-access-client-secret/versions/"
        )
      ) OR
      (
        protoPayload.authenticationInfo.principalEmail="fighter-cleanup@${var.gcp_project_id}.iam.gserviceaccount.com" AND NOT (
          protoPayload.resourceName:"/secrets/fighter-db-app-password/versions/" OR
          protoPayload.resourceName:"/secrets/fighter-cleanup-cf-db-access-client-id/versions/" OR
          protoPayload.resourceName:"/secrets/fighter-cleanup-cf-db-access-client-secret/versions/"
        )
      ) OR
      protoPayload.authenticationInfo.principalEmail="fighter-notes-deployer@${var.gcp_project_id}.iam.gserviceaccount.com" OR
      protoPayload.authenticationInfo.principalEmail="fighter-cleanup-scheduler@${var.gcp_project_id}.iam.gserviceaccount.com"
    )
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

resource "google_logging_metric" "fighter_control_plane_change" {
  name        = "fighter_control_plane_change"
  description = "IAM, WIF, audit, protected logging, and cleanup schedule configuration changes"
  project     = var.gcp_project_id
  filter      = <<-EOT
    log_id("cloudaudit.googleapis.com/activity") AND (
      protoPayload.serviceName="iam.googleapis.com" OR
      (
        protoPayload.serviceName="cloudresourcemanager.googleapis.com" AND
        protoPayload.methodName:"SetIamPolicy"
      ) OR
      (
        protoPayload.serviceName="logging.googleapis.com" AND (
          protoPayload.resourceName:"fighter-security" OR
          protoPayload.resourceName:"fighter-security-audit"
        )
      ) OR
      (
        protoPayload.serviceName="cloudscheduler.googleapis.com" AND
        protoPayload.resourceName:"fighter-cleanup-daily"
      )
    )
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

resource "google_logging_metric" "fighter_migration_execution" {
  name        = "fighter_migration_execution"
  description = "Every Fighter migration execution; verify it matches an approved window"
  project     = var.gcp_project_id
  filter      = <<-EOT
    log_id("cloudaudit.googleapis.com/system_event")
    resource.type="cloud_run_job"
    resource.labels.job_name="fighter-migration"
    protoPayload.methodName="/Jobs.RunJob"
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

resource "google_logging_metric" "fighter_cleanup_failure" {
  name        = "fighter_cleanup_failure"
  description = "Error emitted by the independent Fighter expiry cleanup job"
  project     = var.gcp_project_id
  filter      = <<-EOT
    resource.type="cloud_run_job"
    resource.labels.job_name="fighter-cleanup"
    severity>=ERROR
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

resource "google_logging_metric" "fighter_cleanup_schedule_failure" {
  name        = "fighter_cleanup_schedule_failure"
  description = "Cloud Scheduler failed to invoke the Fighter expiry cleanup job"
  project     = var.gcp_project_id
  filter      = <<-EOT
    resource.type="cloud_scheduler_job"
    resource.labels.job_id="fighter-cleanup-daily"
    severity>=ERROR
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

resource "google_logging_metric" "fighter_cleanup_success" {
  name        = "fighter_cleanup_success"
  description = "Successful completion of the independent Fighter expiry cleanup job"
  project     = var.gcp_project_id
  filter      = <<-EOT
    resource.type="cloud_run_job"
    resource.labels.job_name="fighter-cleanup"
    textPayload:"Fighter cleanup completed:"
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

resource "google_logging_metric" "fighter_share_quota_rejection" {
  name        = "fighter_share_quota_rejection"
  description = "Share creation rejected by a global hard quota"
  project     = var.gcp_project_id
  filter      = <<-EOT
    resource.type="cloud_run_revision"
    resource.labels.service_name="fighter"
    textPayload:"Published analysis create quota reached"
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

resource "google_monitoring_notification_channel" "fighter_security_email" {
  project      = var.gcp_project_id
  display_name = "Fighter security alerts"
  type         = "email"

  labels = {
    email_address = var.owner_email
  }

  user_labels = {
    app     = "fighter"
    purpose = "security"
  }

  depends_on = [google_project_service.required]
}

resource "google_monitoring_alert_policy" "fighter_default_sa_secret_read" {
  project      = var.gcp_project_id
  display_name = "Fighter: default SA accessed Secret Manager"
  combiner     = "OR"
  enabled      = true
  notification_channels = [
    google_monitoring_notification_channel.fighter_security_email.name,
  ]

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

resource "google_monitoring_alert_policy" "fighter_unexpected_secret_read" {
  project      = var.gcp_project_id
  display_name = "Fighter: unexpected Secret Manager access"
  combiner     = "OR"
  enabled      = true
  notification_channels = [
    google_monitoring_notification_channel.fighter_security_email.name,
  ]

  conditions {
    display_name = "Any allowlist violation or deployer secret read"
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.fighter_unexpected_secret_read.name}\" AND resource.type=\"audited_resource\""
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
    content   = "Treat this as a credential-boundary incident. Identify principal and secret resource in Data Access logs; never export secret payloads."
    mime_type = "text/markdown"
  }
}

resource "google_monitoring_alert_policy" "fighter_control_plane_change" {
  project      = var.gcp_project_id
  display_name = "Fighter: IAM, WIF, or audit configuration changed"
  combiner     = "OR"
  enabled      = true
  notification_channels = [
    google_monitoring_notification_channel.fighter_security_email.name,
  ]

  conditions {
    display_name = "Any audited control-plane change"
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.fighter_control_plane_change.name}\" AND resource.type=\"audited_resource\""
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
    content   = "Confirm the actor and corresponding reviewed infrastructure change. Revert unauthorized IAM, WIF, audit, or log-routing changes."
    mime_type = "text/markdown"
  }
}

resource "google_monitoring_alert_policy" "fighter_migration_execution" {
  project      = var.gcp_project_id
  display_name = "Fighter: production migration executed"
  combiner     = "OR"
  enabled      = true
  notification_channels = [
    google_monitoring_notification_channel.fighter_security_email.name,
  ]

  conditions {
    display_name = "Any migration job execution"
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.fighter_migration_execution.name}\" AND resource.type=\"cloud_run_job\""
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
    content   = "Match the execution timestamp and digest to an approved Run Production Migration workflow and backup confirmation."
    mime_type = "text/markdown"
  }
}

resource "google_monitoring_alert_policy" "fighter_cleanup_failure" {
  project      = var.gcp_project_id
  display_name = "Fighter: expiry cleanup failed"
  combiner     = "OR"
  enabled      = true
  notification_channels = [
    google_monitoring_notification_channel.fighter_security_email.name,
  ]

  conditions {
    display_name = "Any cleanup job error"
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.fighter_cleanup_failure.name}\" AND resource.type=\"cloud_run_job\""
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
    content   = "Inspect the cleanup execution without logging row IDs or tokens. Restore DB/tunnel access and execute fighter-cleanup manually within 24 hours."
    mime_type = "text/markdown"
  }
}

resource "google_monitoring_alert_policy" "fighter_cleanup_schedule_failure" {
  project      = var.gcp_project_id
  display_name = "Fighter: expiry cleanup schedule failed"
  combiner     = "OR"
  enabled      = true
  notification_channels = [
    google_monitoring_notification_channel.fighter_security_email.name,
  ]

  conditions {
    display_name = "Cloud Scheduler could not start the cleanup job"
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.fighter_cleanup_schedule_failure.name}\" AND resource.type=\"cloud_scheduler_job\""
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
    content   = "Inspect fighter-cleanup-daily authentication and the Cloud Run Jobs API response. Correct the schedule or IAM failure and execute fighter-cleanup manually within 24 hours."
    mime_type = "text/markdown"
  }
}

resource "google_monitoring_alert_policy" "fighter_cleanup_overdue" {
  project      = var.gcp_project_id
  display_name = "Fighter: expiry cleanup overdue"
  combiner     = "OR"
  enabled      = true
  notification_channels = [
    google_monitoring_notification_channel.fighter_security_email.name,
  ]

  conditions {
    display_name = "No successful cleanup for 25 hours"
    condition_absent {
      filter   = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.fighter_cleanup_success.name}\" AND resource.type=\"cloud_run_job\""
      duration = "90000s"
    }
  }

  documentation {
    content   = "Confirm the initial success metric exists, inspect fighter-cleanup-daily and the Cloud Run execution, and execute fighter-cleanup manually within 24 hours."
    mime_type = "text/markdown"
  }
}

resource "google_monitoring_alert_policy" "fighter_share_quota_rejection" {
  project      = var.gcp_project_id
  display_name = "Fighter: anonymous share hard quota reached"
  combiner     = "OR"
  enabled      = true
  notification_channels = [
    google_monitoring_notification_channel.fighter_security_email.name,
  ]

  conditions {
    display_name = "Any global quota rejection"
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.fighter_share_quota_rejection.name}\" AND resource.type=\"cloud_run_revision\""
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
    content   = "Creation is failing closed. Check daily events, active rows, relation bytes, cleanup lag, and Cloudflare traffic before changing a limit."
    mime_type = "text/markdown"
  }
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

resource "google_project_iam_member" "fighter_cleanup_scheduler_invoker" {
  project = var.gcp_project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.fighter_cleanup_scheduler.email}"

  condition {
    title       = "fighter_cleanup_job_invocation_only"
    description = "Allow the scheduler to execute only the Fighter cleanup Job"
    expression  = "resource.type == 'run.googleapis.com/Job' && resource.name.endsWith('/jobs/fighter-cleanup')"
  }
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
    google_project_iam_member.fighter_cleanup_scheduler_invoker,
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

# Runtime workloads must never publish container images. The legacy default
# Compute SA currently inherits Editor for other applications, so an explicit
# deny closes this upload path immediately without waiting for every app to be
# migrated off that identity. Project administrators remain the break-glass
# control plane; the Fighter builder is the only workload writer for its repo.
resource "google_iam_deny_policy" "default_compute_no_artifact_upload" {
  parent          = urlencode("cloudresourcemanager.googleapis.com/projects/${var.gcp_project_id}")
  name            = "default-compute-no-artifact-upload"
  display_name    = "Default Compute SA cannot upload container artifacts"
  deletion_policy = "PREVENT"

  rules {
    description = "Prevent compromised runtime workloads from publishing images"

    deny_rule {
      denied_principals = [
        "principal://iam.googleapis.com/projects/-/serviceAccounts/${local.fighter_default_compute_service_account}",
      ]
      denied_permissions = [
        "artifactregistry.googleapis.com/repositories.uploadArtifacts",
      ]
    }
  }

  depends_on = [
    google_project_iam_member.terraform_github["roles/iam.denyAdmin"],
  ]
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
