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
    # Repository part of the GitHub OIDC `sub` claim. The repo has opted into
    # the immutable subject claim, so it is `<owner>@<owner_id>/<repo>@<repo_id>`
    # rather than the name-only form. The same string is matched exactly by
    # opkssh in nixos/services/opkssh.nix (used by apply-nixos.yml, which runs
    # in the same `apply` environment), so it is verified in production.
    github_sub_prefix = "repo:yuniruyuni@85034901/yuniruyuni.net@1181770564"
  }
}

# -----------------------------------------------------------------------------
# State bucket (holds this very state file — prevent_destroy is mandatory)
# -----------------------------------------------------------------------------

resource "google_storage_bucket" "terraform_state" {
  name                        = local.ci.state_bucket
  location                    = local.ci.state_bucket_region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
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
    "roles/logging.configWriter",
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

# Each SA can only be impersonated by jobs running in its GitHub environment.
#
# GitHub puts `:environment:<name>` at the end of `sub` for any job that
# declares `environment:`, so binding on google.subject (= assertion.sub)
# pins both the repository (by immutable id) and the environment:
#
# - apply SA: only `environment: apply` (apply-terraform.yml). The apply
#   environment only accepts deployments from `main`, so PR code — including
#   plan jobs, which run PR code with an OIDC token — cannot reach roles/editor
#   / iam.securityAdmin.
# - plan SA: only `environment: plan` (plan-terraform.yml, trigger-plan.yml).
#
# Previously both SAs were bound to attribute.repository, which any job in the
# repository satisfies.
#
# NOTE: changing a workflow's `environment:` (or the repo's sub customization)
# breaks these bindings. Update them together.

resource "google_service_account_iam_member" "workload_identity_user_apply_env" {
  service_account_id = google_service_account.terraform_github.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principal://iam.googleapis.com/${google_iam_workload_identity_pool.ci.name}/subject/${local.ci.github_sub_prefix}:environment:apply"
}

resource "google_service_account_iam_member" "workload_identity_user_plan_env" {
  service_account_id = google_service_account.terraform_github_plan.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principal://iam.googleapis.com/${google_iam_workload_identity_pool.ci.name}/subject/${local.ci.github_sub_prefix}:environment:plan"
}
