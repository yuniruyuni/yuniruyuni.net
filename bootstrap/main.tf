provider "google" {
  project = var.project_id
  region  = var.region
}

# =============================================================================
# API有効化
# =============================================================================

locals {
  required_apis = [
    "storage.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "cloudresourcemanager.googleapis.com",
  ]
}

resource "google_project_service" "required" {
  for_each = toset(local.required_apis)

  project = var.project_id
  service = each.value

  # API無効化時にリソースを削除しない
  disable_on_destroy = false
}

# =============================================================================
# Terraform State
# =============================================================================

# Terraform State用GCSバケット
resource "google_storage_bucket" "terraform_state" {
  name     = "${var.project_id}-terraform-state"
  location = var.region

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 5
    }
    action {
      type = "Delete"
    }
  }

  uniform_bucket_level_access = true

  # 誤削除防止
  force_destroy = false

  depends_on = [google_project_service.required]
}

# =============================================================================
# Service Account
# =============================================================================

# GitHub Actions用Service Account
resource "google_service_account" "terraform_github" {
  account_id   = "terraform-github"
  display_name = "Terraform GitHub Actions"
  description  = "Service account for Terraform operations from GitHub Actions"

  depends_on = [google_project_service.required]
}

# Project-level roles (IaC管理)
resource "google_project_iam_member" "terraform_github" {
  for_each = toset([
    "roles/editor",
    "roles/iam.securityAdmin",
    "roles/iam.workloadIdentityPoolAdmin",
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.terraform_github.email}"
}

# GCS権限
resource "google_storage_bucket_iam_member" "terraform_state_admin" {
  bucket = google_storage_bucket.terraform_state.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.terraform_github.email}"
}

# =============================================================================
# Plan-only Service Account (read-only)
# =============================================================================

resource "google_service_account" "terraform_github_plan" {
  account_id   = "terraform-github-plan"
  display_name = "Terraform GitHub Actions (Plan)"
  description  = "Read-only service account for terraform plan from GitHub Actions"

  depends_on = [google_project_service.required]
}

# Project-level read-only roles
resource "google_project_iam_member" "terraform_github_plan" {
  for_each = toset([
    "roles/viewer",
    "roles/iam.securityReviewer",
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.terraform_github_plan.email}"
}

# State bucket access (locking requires read-write)
resource "google_storage_bucket_iam_member" "terraform_state_plan" {
  bucket = google_storage_bucket.terraform_state.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.terraform_github_plan.email}"
}

# =============================================================================
# Workload Identity
# =============================================================================

# Workload Identity Pool
resource "google_iam_workload_identity_pool" "github_actions" {
  workload_identity_pool_id = "github-actions"
  display_name              = "GitHub Actions"
  description               = "Workload Identity Pool for GitHub Actions OIDC"

  depends_on = [google_project_service.required]
}

# OIDC Provider
resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_actions.workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  display_name                       = "GitHub"
  description                        = "GitHub OIDC Provider"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
  }

  attribute_condition = "assertion.repository_owner == '${var.github_org}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Service AccountへのWorkload Identityバインド
resource "google_service_account_iam_member" "workload_identity_user" {
  service_account_id = google_service_account.terraform_github.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_actions.name}/attribute.repository/${var.github_org}/${var.github_repo}"
}

# Plan SA へのWorkload Identityバインド
resource "google_service_account_iam_member" "workload_identity_user_plan" {
  service_account_id = google_service_account.terraform_github_plan.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_actions.name}/attribute.repository/${var.github_org}/${var.github_repo}"
}
