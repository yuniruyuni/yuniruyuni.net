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

    # PostgreSQL via VPS Tunnel (TCP proxied through Cloudflare)
    db = { name = "db", type = "CNAME", target = "tunnel_main", proxied = true }

    # GCE Tunnel (CNAME to gce tunnel)
    # Root domain uses CNAME flattening (Cloudflare feature)
    root     = { name = var.zone_name, type = "CNAME", target = "tunnel_gce", proxied = true }
    tags     = { name = "tags", type = "CNAME", target = "tunnel_gce", proxied = true }
    costume  = { name = "costume", type = "CNAME", target = "tunnel_gce", proxied = true }
    lom      = { name = "lom", type = "CNAME", target = "tunnel_gce", proxied = true }
    template = { name = "template", type = "CNAME", target = "tunnel_gce", proxied = true }
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
      # PostgreSQL access (via cloudflared access tcp)
      {
        hostname = "db.${var.zone_name}"
        service  = "tcp://localhost:5432"
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

# cloudflared tunnel token は API から取得せず手元の材料から組み立てる。
# Cloudflare API の GET /cfd_tunnel/:id/token は Tunnel: Edit を要求する一方、
# この値は base64(JSON{a,t,s}) という公開済みの構造で、a/t/s はすべてこの state で所有している。
# ローカル合成により plan 用 API token を Read 権限に留められる。
locals {
  # sensitive() で明示ラップし、plan 出力・PR コメントへの混入を防ぐ。
  # 材料側 (random_password.result / var.cloudflare_account_id) も sensitive のため
  # 本来自動伝播されるが、関数合成を跨いでも確実に redact されるよう保険を掛ける。
  gce_tunnel_token = sensitive(base64encode(jsonencode({
    a = var.cloudflare_account_id
    t = cloudflare_zero_trust_tunnel_cloudflared.gce.id
    s = base64encode(random_password.gce_tunnel_secret.result)
  })))
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
