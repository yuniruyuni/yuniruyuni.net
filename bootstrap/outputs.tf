output "terraform_state_bucket" {
  description = "GCS bucket name for Terraform state"
  value       = google_storage_bucket.terraform_state.name
}

output "workload_identity_provider" {
  description = "Full Workload Identity Provider resource name"
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "service_account_email" {
  description = "Terraform GitHub Actions service account email"
  value       = google_service_account.terraform_github.email
}

output "github_secrets" {
  description = "Values to set as GitHub repository secrets"
  value = {
    GCP_WORKLOAD_IDENTITY_PROVIDER = google_iam_workload_identity_pool_provider.github.name
    GCP_SERVICE_ACCOUNT            = google_service_account.terraform_github.email
  }
}

output "backend_config" {
  description = "Backend configuration for other Terraform configurations"
  value = {
    bucket = google_storage_bucket.terraform_state.name
  }
}
