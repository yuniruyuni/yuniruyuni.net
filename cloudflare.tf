# =============================================================================
# Cloudflare Provider
# =============================================================================

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

data "cloudflare_zone" "main" {
  filter = {
    name = var.zone_name
  }
}

# =============================================================================
# DNS Records (consolidated with for_each)
# =============================================================================

locals {
  dns_records = {
    # VPS Direct (A records)
    wildcard = { name = "*", type = "A", target = "vps", proxied = true }

    # VPS Tunnel (CNAME to main tunnel)
    n8n = { name = "n8n", type = "CNAME", target = "tunnel_main", proxied = true }

    # SSH via VPS Tunnel (proxied through Cloudflare for Zero Trust access)
    ssh = { name = "ssh", type = "CNAME", target = "tunnel_main", proxied = true }

    # GCE Tunnel (CNAME to gce tunnel)
    # Root domain uses CNAME flattening (Cloudflare feature)
    root    = { name = var.zone_name, type = "CNAME", target = "tunnel_gce", proxied = true }
    tags    = { name = "tags", type = "CNAME", target = "tunnel_gce", proxied = true }
    costume = { name = "costume", type = "CNAME", target = "tunnel_gce", proxied = true }
    lom     = { name = "lom", type = "CNAME", target = "tunnel_gce", proxied = true }
  }
}

resource "cloudflare_dns_record" "records" {
  for_each = local.dns_records

  zone_id = data.cloudflare_zone.main.zone_id
  name    = each.value.name
  type    = each.value.type
  content = (
    each.value.target == "vps" ? var.vps_ip_address :
    each.value.target == "tunnel_main" ? "${cloudflare_zero_trust_tunnel_cloudflared.main.id}.cfargotunnel.com" :
    "${cloudflare_zero_trust_tunnel_cloudflared.gce.id}.cfargotunnel.com"
  )
  proxied = each.value.proxied
  ttl     = each.value.proxied ? 1 : 300 # Auto for proxied, 5min for direct
}

# State migration: move old individual resources to new for_each resources
moved {
  from = cloudflare_dns_record.root
  to   = cloudflare_dns_record.records["root"]
}

moved {
  from = cloudflare_dns_record.wildcard
  to   = cloudflare_dns_record.records["wildcard"]
}

moved {
  from = cloudflare_dns_record.n8n
  to   = cloudflare_dns_record.records["n8n"]
}

moved {
  from = cloudflare_dns_record.ssh
  to   = cloudflare_dns_record.records["ssh"]
}

moved {
  from = cloudflare_dns_record.tags
  to   = cloudflare_dns_record.records["tags"]
}

moved {
  from = cloudflare_dns_record.costume
  to   = cloudflare_dns_record.records["costume"]
}

moved {
  from = cloudflare_dns_record.lom
  to   = cloudflare_dns_record.records["lom"]
}

# =============================================================================
# Tunnels
# =============================================================================

# VPS Tunnel (existing - imported)
resource "cloudflare_zero_trust_tunnel_cloudflared" "main" {
  account_id = var.cloudflare_account_id
  name       = "yuniruyuni.net"
  config_src = "cloudflare" # Cloudflare側で設定を管理
}

# VPS Tunnel Configuration (ingress rules)
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "main" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.main.id

  config = {
    ingress = [
      # n8n service
      {
        hostname = "n8n.${var.zone_name}"
        service  = "http://localhost:5678"
      },
      # SSH access
      {
        hostname = "ssh.${var.zone_name}"
        service  = "ssh://localhost:22"
      },
      # Catch-all (required)
      {
        service = "http_status:404"
      }
    ]
  }
}

# GCE Tunnel (for Cloud Run)
resource "random_password" "gce_tunnel_secret" {
  length  = 64
  special = false
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "gce" {
  account_id    = var.cloudflare_account_id
  name          = "gce-cloud-run"
  config_src    = "cloudflare" # Cloudflare側で設定を管理
  tunnel_secret = base64encode(random_password.gce_tunnel_secret.result)
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "gce" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.gce.id
}

# =============================================================================
# GCE Tunnel Configuration (ingress rules)
# =============================================================================

# Cloud Run URLはデータソースから動的に取得
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "gce" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.gce.id

  config = {
    ingress = concat(
      # Cloud Run services (dynamically generated)
      # hostname = "" means root domain (yuniruyuni.net)
      [
        for key, svc in local.cloud_run_services : {
          hostname = svc.hostname == "" ? var.zone_name : "${svc.hostname}.${var.zone_name}"
          service  = data.google_cloud_run_service.services[key].status[0].url
          origin_request = {
            http_host_header = replace(data.google_cloud_run_service.services[key].status[0].url, "https://", "")
          }
        }
      ],
      # Catch-all (required)
      [
        {
          service        = "http_status:404"
          origin_request = null
        }
      ]
    )
  }
}
