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

  # Inline access policy
  policies = [
    {
      name     = "Allow Owner"
      decision = "allow"
      include = [
        {
          email = {
            email = var.owner_email
          }
        }
      ]
    }
  ]
}
