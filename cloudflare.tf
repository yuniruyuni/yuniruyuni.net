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

    # template は Cloud Run から VPS へ移設済み (nixos/services/yunirun.nix)。
    # 向き先は HAProxy の frontend で、その裏に blue/green のコンテナがいる。
    template = { name = "template", type = "CNAME", target = "tunnel_main", proxied = true }

    # StreamerPost も VPS へ移設済み。
    post = { name = "post", type = "CNAME", target = "tunnel_main", proxied = true }

    # costume / lom / web も VPS へ移設済み。
    # root は CNAME flattening でルートドメイン (yuniruyuni.net) を web に向ける。
    costume = { name = "costume", type = "CNAME", target = "tunnel_main", proxied = true }
    lom     = { name = "lom", type = "CNAME", target = "tunnel_main", proxied = true }
    root    = { name = var.zone_name, type = "CNAME", target = "tunnel_main", proxied = true }
    tags    = { name = "tags", type = "CNAME", target = "tunnel_main", proxied = true }

    # fighter も VPS へ移設済み。GCE トンネルの利用者はこれで居なくなった。
    fighter = { name = "fighter", type = "CNAME", target = "tunnel_main", proxied = true }
  }
}

resource "cloudflare_dns_record" "records" {
  for_each = local.dns_records

  zone_id = data.cloudflare_zone.main.zone_id
  name    = each.value.name
  type    = each.value.type
  # 行き先は VPS の IP か VPS のトンネルの 2 つだけ。Cloud Run を前に
  # 置いていた GCE トンネルは、全アプリを VPS へ移したので撤去した。
  content = (
    each.value.target == "vps" ? var.vps_ip_address :
    "${cloudflare_zero_trust_tunnel_cloudflared.main.id}.cfargotunnel.com"
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
      # template。yunirun 管理下の HAProxy の frontend を向く
      # (services/yunirun.nix)。撤去した apps.nix 側の 8100 からの切り替え。
      {
        hostname = "template.${var.zone_name}"
        service  = "http://localhost:8200"
      },
      # StreamerPost。同じく HAProxy の frontend を向く。
      {
        hostname = "post.${var.zone_name}"
        service  = "http://localhost:8240"
      },
      {
        hostname = "costume.${var.zone_name}"
        service  = "http://localhost:8210"
      },
      {
        hostname = "lom.${var.zone_name}"
        service  = "http://localhost:8220"
      },
      # ルートドメイン (web)
      {
        hostname = var.zone_name
        service  = "http://localhost:8230"
      },
      {
        hostname = "tags.${var.zone_name}"
        service  = "http://localhost:8250"
      },
      # fighter。Cloud Run から VPS へ移設した。DB は元から VPS の
      # PostgreSQL なので、アプリが DB の隣へ来たことになる。
      {
        hostname = "fighter.${var.zone_name}"
        service  = "http://localhost:8260"
      },
      # Catch-all (required)
      {
        service = "http_status:404"
      }
    ]
  }
}

# Cloud Run URLはデータソースから動的に取得
