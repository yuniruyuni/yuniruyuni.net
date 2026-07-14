# =============================================================================
# Fighter Notes public sharing abuse controls
# =============================================================================
# Database quotas remain the hard global limit. These edge rules reduce the
# number of requests that ever reach Cloud Run/PostgreSQL.

resource "cloudflare_ruleset" "fighter_rate_limits" {
  zone_id     = data.cloudflare_zone.main.zone_id
  name        = "Fighter Notes rate limits"
  description = "Bound anonymous share create, delete, and random-ID reads"
  kind        = "zone"
  phase       = "http_ratelimit"

  rules = [
    {
      ref         = "fighter_share_create"
      description = "Challenge burst share creation"
      expression  = "(http.host eq \"fighter.${var.zone_name}\" and http.request.method eq \"POST\" and http.request.uri.path eq \"/api/trpc/publishedAnalysis.create\")"
      action      = "managed_challenge"
      enabled     = true
      ratelimit = {
        characteristics     = ["cf.colo.id", "ip.src"]
        period              = 60
        requests_per_period = 10
        mitigation_timeout  = 60
        requests_to_origin  = true
      }
    },
    {
      ref         = "fighter_share_delete"
      description = "Block delete-token brute force"
      expression  = "(http.host eq \"fighter.${var.zone_name}\" and http.request.method eq \"POST\" and http.request.uri.path eq \"/api/trpc/publishedAnalysis.delete\")"
      action      = "block"
      enabled     = true
      ratelimit = {
        characteristics     = ["cf.colo.id", "ip.src"]
        period              = 60
        requests_per_period = 30
        mitigation_timeout  = 60
        requests_to_origin  = true
      }
    },
    {
      ref         = "fighter_share_read"
      description = "Block random share-ID database scans"
      expression  = "(http.host eq \"fighter.${var.zone_name}\" and http.request.method eq \"GET\" and starts_with(http.request.uri.path, \"/s/\"))"
      action      = "block"
      enabled     = true
      ratelimit = {
        characteristics     = ["cf.colo.id", "ip.src"]
        period              = 60
        requests_per_period = 120
        mitigation_timeout  = 60
        requests_to_origin  = true
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
