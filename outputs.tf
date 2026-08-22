# =============================================================================
# Cloudflare Outputs
# =============================================================================

output "cloudflare_zone_id" {
  description = "Cloudflare Zone ID"
  value       = data.cloudflare_zone.main.zone_id
  sensitive   = true
}

output "cloudflare_zone_name" {
  description = "Cloudflare Zone name"
  value       = data.cloudflare_zone.main.name
}
# =============================================================================
# GCP Outputs
# =============================================================================

# =============================================================================
# Cloudflare Access client IDs — values to register in app GitHub secrets
# =============================================================================

# Marked sensitive not because the value is a credential (it is the identifier
# sent in the CF-Access-Client-Id header) but because plan output is posted to
# PR comments on this public repository.

output "cf_db_access_client_id" {
  description = "Shared DB tunnel client ID (CF_DB_ACCESS_CLIENT_ID in template / StreamTagInventory)"
  value       = cloudflare_zero_trust_access_service_token.cloud_run_db.client_id
  sensitive   = true
}

# =============================================================================
# CI (terraform-itself) Outputs — values to register in GitHub secrets
# =============================================================================

output "ci_workload_identity_provider" {
  description = "Workload Identity Provider for Terraform CI (GCP_WORKLOAD_IDENTITY_PROVIDER)"
  value       = google_iam_workload_identity_pool_provider.ci_github.name
  sensitive   = true
}

output "ci_apply_service_account" {
  description = "Apply SA email (GCP_SERVICE_ACCOUNT in apply environment)"
  value       = google_service_account.terraform_github.email
}

output "ci_plan_service_account" {
  description = "Plan SA email (GCP_SERVICE_ACCOUNT in plan environment)"
  value       = google_service_account.terraform_github_plan.email
}
