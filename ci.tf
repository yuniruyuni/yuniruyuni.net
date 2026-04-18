# =============================================================================
# CI Infrastructure
# =============================================================================
#
# State bucket, CI service accounts, and GitHub Actions Workload Identity
# Federation. Every resource here is created once by scripts/bootstrap.sh
# (gcloud) and then imported into this state, so subsequent adjustments go
# through the normal PR -> code owner review -> CI apply flow.
#
# DR / fresh-env setup: run scripts/bootstrap.sh once, then push this repo.

locals {
  ci = {
    state_bucket        = "${var.gcp_project_id}-terraform-state"
    state_bucket_region = "asia-northeast1"
    apply_sa_id         = "terraform-github"
    plan_sa_id          = "terraform-github-plan"
    wif_pool_id         = "github-actions"
    wif_provider_id     = "github"
    # GitHub repo that is allowed to impersonate the CI SAs.
    github_repo = "yuniruyuni/yuniruyuni.net"
  }
}

# -----------------------------------------------------------------------------
# State bucket (holds this very state file — prevent_destroy is mandatory)
# -----------------------------------------------------------------------------

resource "google_storage_bucket" "terraform_state" {
  name                        = local.ci.state_bucket
  location                    = local.ci.state_bucket_region
  uniform_bucket_level_access = true
  force_destroy               = false

  versioning {
    enabled = true
  }

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [google_project_service.required]
}

# -----------------------------------------------------------------------------
# Apply SA — GitHub Actions uses this via WIF for `terraform apply` on main
# -----------------------------------------------------------------------------

resource "google_service_account" "terraform_github" {
  account_id   = local.ci.apply_sa_id
  display_name = "Terraform GitHub Actions"
  description  = "Service account for Terraform apply from GitHub Actions"

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_project_iam_member" "terraform_github" {
  for_each = toset([
    "roles/editor",
    "roles/iam.securityAdmin",
    "roles/iam.workloadIdentityPoolAdmin",
  ])
  project = var.gcp_project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.terraform_github.email}"
}

resource "google_storage_bucket_iam_member" "terraform_state_admin" {
  bucket = google_storage_bucket.terraform_state.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.terraform_github.email}"
}

# -----------------------------------------------------------------------------
# Plan SA — GitHub Actions uses this via WIF for `terraform plan` on PRs.
# Read-only: objectViewer on state bucket, plan runs with -lock=false so no
# create/delete on lock objects is needed. This closes the state-tampering
# path from any plan-time credential leak.
# -----------------------------------------------------------------------------

resource "google_service_account" "terraform_github_plan" {
  account_id   = local.ci.plan_sa_id
  display_name = "Terraform GitHub Actions (Plan)"
  description  = "Read-only service account for terraform plan from GitHub Actions"
}

resource "google_project_iam_member" "terraform_github_plan" {
  for_each = toset([
    "roles/viewer",
    "roles/iam.securityReviewer",
  ])
  project = var.gcp_project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.terraform_github_plan.email}"
}

resource "google_storage_bucket_iam_member" "terraform_state_plan" {
  bucket = google_storage_bucket.terraform_state.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.terraform_github_plan.email}"
}

# -----------------------------------------------------------------------------
# Workload Identity Pool for CI SAs (separate from the apps pool in gcp.tf).
# -----------------------------------------------------------------------------

resource "google_iam_workload_identity_pool" "ci" {
  workload_identity_pool_id = local.ci.wif_pool_id
  display_name              = "GitHub Actions"
  description               = "Workload Identity Pool for Terraform CI (apply / plan SAs)"

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_iam_workload_identity_pool_provider" "ci_github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.ci.workload_identity_pool_id
  workload_identity_pool_provider_id = local.ci.wif_provider_id
  display_name                       = "GitHub"
  description                        = "GitHub OIDC Provider for Terraform CI"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
  }

  attribute_condition = "assertion.repository_owner == '${split("/", local.ci.github_repo)[0]}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account_iam_member" "workload_identity_user_apply" {
  service_account_id = google_service_account.terraform_github.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.ci.name}/attribute.repository/${local.ci.github_repo}"
}

resource "google_service_account_iam_member" "workload_identity_user_plan" {
  service_account_id = google_service_account.terraform_github_plan.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.ci.name}/attribute.repository/${local.ci.github_repo}"
}
