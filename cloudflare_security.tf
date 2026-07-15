# =============================================================================
# Fighter Notes public sharing abuse controls
# =============================================================================
# The live zone uses Cloudflare Free, which permits one IP-based rate-limiting
# rule, a 10-second counting period, and mitigation_timeout=0 for challenge
# actions. Combine the two DB-backed share paths into that one path-only rule;
# application limits, database timeouts, and global hard quotas remain the
# precise per-operation backstop at origin.
# https://developers.cloudflare.com/waf/rate-limiting-rules/

resource "cloudflare_ruleset" "fighter_rate_limits" {
  zone_id     = data.cloudflare_zone.main.zone_id
  name        = "Fighter Notes share abuse rate limit"
  description = "Challenge burst create and random-ID reads within Free-plan limits"
  kind        = "zone"
  phase       = "http_ratelimit"

  rules = [
    {
      ref         = "fighter_share_abuse"
      description = "Challenge burst DB-backed share operations"
      expression  = "(starts_with(http.request.uri.path, \"/api/trpc/publishedAnalysis.create\") or starts_with(http.request.uri.path, \"/s/\"))"
      action      = "managed_challenge"
      enabled     = true
      ratelimit = {
        characteristics     = ["cf.colo.id", "ip.src"]
        period              = 10
        requests_per_period = 20
        mitigation_timeout  = 0
      }
    },
  ]
}

resource "cloudflare_ruleset" "fighter_share_cache" {
  zone_id     = data.cloudflare_zone.main.zone_id
  name        = "Fighter Notes share cache policy"
  description = "Cache immutable share HTML according to origin lifecycle headers"
  kind        = "zone"
  phase       = "http_request_cache_settings"

  rules = [
    {
      ref         = "fighter_share_cache_eligible"
      description = "Cache immutable public shares while respecting origin no-store"
      expression  = "(http.host eq \"fighter.${var.zone_name}\" and starts_with(http.request.uri.path, \"/s/\"))"
      action      = "set_cache_settings"
      action_parameters = {
        cache = true
        edge_ttl = {
          mode = "respect_origin"
        }
        browser_ttl = {
          mode = "respect_origin"
        }
        cache_key = {
          custom_key = {
            query_string = {
              exclude = {
                all = true
              }
            }
          }
        }
        serve_stale = {
          disable_stale_while_updating = false
        }
      }
      enabled = true
    },
  ]
}
