# =============================================================================
# Cloudflare Outputs
# =============================================================================

output "cloudflare_zone_id" {
  description = "Cloudflare Zone ID"
  value       = data.cloudflare_zone.main.zone_id
}

output "cloudflare_zone_name" {
  description = "Cloudflare Zone name"
  value       = data.cloudflare_zone.main.name
}

output "gce_tunnel_id" {
  description = "GCE Tunnel ID"
  value       = cloudflare_zero_trust_tunnel_cloudflared.gce.id
}

# =============================================================================
# GCP Outputs
# =============================================================================

output "workload_identity_provider" {
  description = "Workload Identity Provider for GitHub Actions"
  value       = google_iam_workload_identity_pool_provider.github_actions.name
}

output "deployer_service_account" {
  description = "Service account email for app deployment"
  value       = google_service_account.github_apps_deployer.email
}

output "tunnel_gateway_instance" {
  description = "Tunnel gateway instance name"
  value       = google_compute_instance.tunnel_gateway.name
}

output "tunnel_gateway_service_account" {
  description = "Tunnel gateway service account email"
  value       = google_service_account.tunnel_gateway.email
}
