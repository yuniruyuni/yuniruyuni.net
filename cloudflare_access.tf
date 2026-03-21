# =============================================================================
# Zero Trust Access - Identity Providers
# =============================================================================

# Google OAuth (primary authentication)
resource "cloudflare_zero_trust_access_identity_provider" "google" {
  account_id = var.cloudflare_account_id
  name       = "Google"
  type       = "google"

  config = {
    client_id     = var.google_oauth_client_id
    client_secret = var.google_oauth_client_secret
  }
}

# =============================================================================
# Zero Trust Access - Reusable Policy
# =============================================================================

resource "cloudflare_zero_trust_access_policy" "owner" {
  account_id = var.cloudflare_account_id
  name       = "Owner"
  decision   = "allow"

  include = [{
    email = {
      email = var.owner_email
    }
  }]
}

# =============================================================================
# Zero Trust Access - Applications
# =============================================================================

locals {
  access_applications = {
    n8n = {
      name   = "n8n"
      domain = "n8n.${var.zone_name}"
    }
  }
}

resource "cloudflare_zero_trust_access_application" "apps" {
  for_each = local.access_applications

  zone_id          = data.cloudflare_zone.main.zone_id
  name             = each.value.name
  domain           = each.value.domain
  type             = "self_hosted"
  session_duration = "24h"

  allowed_idps              = [cloudflare_zero_trust_access_identity_provider.google.id]
  auto_redirect_to_identity = true

  policies = [{
    id         = cloudflare_zero_trust_access_policy.owner.id
    precedence = 1
  }]
}

# =============================================================================
# Zero Trust Access - PostgreSQL DB (TCP, service token auth)
# =============================================================================

# Service token for Cloud Run → DB tunnel authentication
resource "cloudflare_zero_trust_access_service_token" "cloud_run_db" {
  account_id = var.cloudflare_account_id
  name       = "Cloud Run DB Access"
}

# Policy: allow service token (for automated Cloud Run access)
resource "cloudflare_zero_trust_access_policy" "cloud_run_db" {
  account_id = var.cloudflare_account_id
  name       = "Cloud Run DB Service Token"
  decision   = "non_identity"

  include = [{
    service_token = {
      token_id = cloudflare_zero_trust_access_service_token.cloud_run_db.id
    }
  }]
}

# Access application for db.yuniruyuni.net
resource "cloudflare_zero_trust_access_application" "db" {
  zone_id          = data.cloudflare_zone.main.zone_id
  name             = "PostgreSQL"
  domain           = "db.${var.zone_name}"
  type             = "self_hosted"
  session_duration = "24h"

  policies = [
    {
      id         = cloudflare_zero_trust_access_policy.cloud_run_db.id
      precedence = 1
    },
    {
      id         = cloudflare_zero_trust_access_policy.owner.id
      precedence = 2
    }
  ]
}
