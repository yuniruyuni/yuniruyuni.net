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
