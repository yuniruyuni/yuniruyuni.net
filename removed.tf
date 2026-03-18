# =============================================================================
# Removed Resources
# =============================================================================
# These blocks tell Terraform to forget about resources without destroying them.
# Use when API permissions are insufficient or resources were deleted externally.

# IronClaw Access Application - removed due to migration to NanoClaw/Discord
# API token lacks Zero Trust permissions, so we can't destroy via API
removed {
  from = cloudflare_zero_trust_access_application.ironclaw

  lifecycle {
    destroy = false
  }
}
