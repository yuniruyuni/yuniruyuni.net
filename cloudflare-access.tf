# =============================================================================
# Cloudflare Access - Zero Trust Protection
# =============================================================================

# IronClaw AI Agent - Protected by email authentication
resource "cloudflare_zero_trust_access_application" "ironclaw" {
  zone_id          = data.cloudflare_zone.main.zone_id
  name             = "IronClaw Agent API"
  domain           = "agent.${var.zone_name}"
  type             = "self_hosted"
  session_duration = "24h"
}

# Reusable Access Policy for IronClaw
resource "cloudflare_zero_trust_access_policy" "ironclaw_allow_owner" {
  account_id = var.cloudflare_account_id
  name       = "Allow Owner for IronClaw"
  decision   = "allow"

  include = [
    {
      email = {
        email = var.owner_email
      }
    }
  ]
}
