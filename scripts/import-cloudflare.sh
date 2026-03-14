#!/bin/bash
set -euo pipefail

# Cloudflare既存リソースのImportスクリプト
# 使用前に以下の環境変数を設定してください:
#   CLOUDFLARE_API_TOKEN
#   CLOUDFLARE_ZONE_ID
#   CLOUDFLARE_ACCOUNT_ID

cd "$(dirname "$0")/../cloudflare"

echo "=== Cloudflare Resource Import Script ==="

# 環境変数チェック
if [[ -z "${CLOUDFLARE_API_TOKEN:-}" ]]; then
  echo "Error: CLOUDFLARE_API_TOKEN is not set"
  exit 1
fi

if [[ -z "${CLOUDFLARE_ZONE_ID:-}" ]]; then
  echo "Error: CLOUDFLARE_ZONE_ID is not set"
  exit 1
fi

if [[ -z "${CLOUDFLARE_ACCOUNT_ID:-}" ]]; then
  echo "Error: CLOUDFLARE_ACCOUNT_ID is not set"
  exit 1
fi

echo ""
echo "=== Generating DNS Records ==="
cf-terraforming generate \
  --resource-type cloudflare_dns_record \
  --zone "$CLOUDFLARE_ZONE_ID" > dns.tf.generated

echo ""
echo "=== Generating DNS Import Blocks ==="
cf-terraforming import \
  --resource-type cloudflare_dns_record \
  --zone "$CLOUDFLARE_ZONE_ID" \
  --modern-import-block > import_dns.tf

echo ""
echo "=== Generating Tunnel Configuration ==="
cf-terraforming generate \
  --resource-type cloudflare_zero_trust_tunnel_cloudflared \
  --account "$CLOUDFLARE_ACCOUNT_ID" > tunnel.tf.generated || echo "No tunnels found or error occurred"

echo ""
echo "=== Generating Tunnel Import Blocks ==="
cf-terraforming import \
  --resource-type cloudflare_zero_trust_tunnel_cloudflared \
  --account "$CLOUDFLARE_ACCOUNT_ID" \
  --modern-import-block > import_tunnel.tf || echo "No tunnels to import or error occurred"

echo ""
echo "=== Generated Files ==="
ls -la *.generated *.tf 2>/dev/null || true

echo ""
echo "=== Next Steps ==="
echo "1. Review generated files (*.tf.generated)"
echo "2. Merge generated content into dns.tf and tunnel.tf"
echo "3. Run: terraform init"
echo "4. Run: terraform plan (should show imports)"
echo "5. Run: terraform apply"
echo "6. Run: terraform plan (should show 'No changes')"
echo "7. Delete import_*.tf and *.generated files"
