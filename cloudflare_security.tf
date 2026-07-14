# =============================================================================
# Fighter Notes public sharing abuse controls
# =============================================================================
# The live zone uses Cloudflare Free, which permits one IP-based rate-limiting
# rule, a 10-second counting period, and mitigation_timeout=0 for challenge
# actions. Protect the costliest create path at the edge; application limits,
# database timeouts, and global hard quotas bound reads and deletes at origin.
# https://developers.cloudflare.com/waf/rate-limiting-rules/

resource "cloudflare_ruleset" "fighter_rate_limits" {
  zone_id     = data.cloudflare_zone.main.zone_id
  name        = "Fighter Notes share creation rate limit"
  description = "Challenge burst anonymous share creation within Free-plan limits"
  kind        = "zone"
  phase       = "http_ratelimit"

  rules = [
    {
      ref         = "fighter_share_create"
      description = "Challenge burst share creation"
      expression  = "(http.request.uri.path eq \"/api/trpc/publishedAnalysis.create\")"
      action      = "managed_challenge"
      enabled     = true
      ratelimit = {
        characteristics     = ["cf.colo.id", "ip.src"]
        period              = 10
        requests_per_period = 10
        mitigation_timeout  = 0
      }
    },
  ]
}

resource "cloudflare_ruleset" "fighter_share_cache" {
  zone_id     = data.cloudflare_zone.main.zone_id
  name        = "Fighter Notes share cache policy"
  description = "Never cache result-specific share HTML at the edge"
  kind        = "zone"
  phase       = "http_request_cache_settings"

  rules = [
    {
      ref         = "fighter_share_cache_bypass"
      description = "Bypass cache for public share result pages"
      expression  = "(http.host eq \"fighter.${var.zone_name}\" and starts_with(http.request.uri.path, \"/s/\"))"
      action      = "set_cache_settings"
      action_parameters = {
        cache = false
      }
      enabled = true
    },
  ]
}
