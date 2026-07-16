# =============================================================================
# Fighter Notes public sharing abuse controls
# =============================================================================
# The live zone uses Cloudflare Free, which permits one IP-based rate-limiting
# rule, a 10-second counting period, and a 10-second block period. Combine the
# two DB-backed share paths into that one path-only rule;
# application limits, database timeouts, and global hard quotas remain the
# precise per-operation backstop at origin.
# https://developers.cloudflare.com/waf/rate-limiting-rules/

resource "cloudflare_ruleset" "fighter_rate_limits" {
  zone_id     = data.cloudflare_zone.main.zone_id
  name        = "Fighter Notes share abuse rate limit"
  description = "Block burst create and random-ID reads within Free-plan limits"
  kind        = "zone"
  phase       = "http_ratelimit"

  rules = [
    {
      ref         = "fighter_share_abuse"
      description = "Block burst DB-backed share operations"
      expression  = "(starts_with(http.request.uri.path, \"/api/trpc/publishedAnalysis.create\") or starts_with(http.request.uri.path, \"/s/\"))"
      action      = "block"
      enabled     = true
      ratelimit = {
        characteristics     = ["cf.colo.id", "ip.src"]
        period              = 10
        requests_per_period = 20
        mitigation_timeout  = 10
      }
    },
  ]
}

# Cloudflare permits only one zone entrypoint ruleset for this phase. The live
# zone already has a default cache rule, so import and preserve that ruleset
# instead of attempting to create a second one.
import {
  to = cloudflare_ruleset.fighter_share_cache
  id = "zones/a8bf81c5ba84f1cb4c64953af0ddb1d8/0bbb1ede251b420f8811dcc9e731fa0e"
}

resource "cloudflare_ruleset" "fighter_share_cache" {
  zone_id     = data.cloudflare_zone.main.zone_id
  name        = "default"
  description = ""
  kind        = "zone"
  phase       = "http_request_cache_settings"

  rules = [
    {
      ref         = "f4098f3683a74ad488ea6570a8a4413b"
      description = "Default"
      expression  = "true"
      action      = "set_cache_settings"
      action_parameters = {
        cache = true
        edge_ttl = {
          mode = "bypass_by_default"
        }
        browser_ttl = {
          mode = "respect_origin"
        }
      }
      enabled = true
    },
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
