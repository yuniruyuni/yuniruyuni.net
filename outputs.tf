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

output "cloudflare_zone_plan" {
  description = "Cloudflare Zone plan used to validate plan-dependent WAF limits"
  value       = data.cloudflare_zone_subscription.main.rate_plan.id
}

output "gce_tunnel_id" {
  description = "GCE Tunnel ID"
  value       = cloudflare_zero_trust_tunnel_cloudflared.gce.id
  sensitive   = true
}

# =============================================================================
# GCP Outputs
# =============================================================================

output "workload_identity_provider" {
  description = "Workload Identity Provider for GitHub Actions"
  value       = google_iam_workload_identity_pool_provider.github_actions.name
  sensitive   = true
}

output "deployer_service_account" {
  description = "Service account email for app deployment"
  value       = google_service_account.github_apps_deployer.email
}

output "fighter_builder_workload_identity_provider" {
  description = "Dedicated WIF provider for Fighter Notes image builds"
  value       = google_iam_workload_identity_pool_provider.fighter_builder.name
  sensitive   = true
}

output "fighter_deployer_workload_identity_provider" {
  description = "Dedicated WIF provider for Fighter Notes production deploys"
  value       = google_iam_workload_identity_pool_provider.fighter_deployer.name
  sensitive   = true
}

output "fighter_builder_service_account" {
  description = "Fighter Notes Artifact Registry builder SA"
  value       = google_service_account.fighter_builder.email
}

output "fighter_deployer_service_account" {
  description = "Fighter Notes resource-scoped Cloud Run deployer SA"
  value       = google_service_account.fighter_deployer.email
}

output "fighter_workload_service_accounts" {
  description = "Dedicated Fighter Notes runtime, migration, and cleanup identities"
  value       = { for name, account in google_service_account.fighter_workload : name => account.email }
}

output "tunnel_gateway_instance" {
  description = "Tunnel gateway instance name"
  value       = google_compute_instance.tunnel_gateway.name
}

output "tunnel_gateway_service_account" {
  description = "Tunnel gateway service account email"
  value       = google_service_account.tunnel_gateway.email
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
