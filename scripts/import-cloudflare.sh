#!/bin/bash
set -euo pipefail

# Cloudflare既存リソースのImportスクリプト
# 使用前に以下の環境変数を設定してください:
#   CLOUDFLARE_API_TOKEN
#   CLOUDFLARE_ZONE_ID
#   CLOUDFLARE_ACCOUNT_ID

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/.generated/cloudflare}"

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

mkdir -p "$OUTPUT_DIR"
cd "$OUTPUT_DIR"

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
echo "2. Compare generated content with root Terraform files:"
echo "   - $REPO_ROOT/cloudflare.tf"
echo "   - $REPO_ROOT/cloudflare_access.tf"
echo "3. If importing new resources, move reviewed import blocks into a temporary root *.tf file"
echo "4. Run from repo root: terraform init && terraform plan"
echo "5. Run: terraform apply"
echo "6. Run: terraform plan (should show 'No changes')"
echo "7. Delete any temporary root import *.tf files; generated files remain ignored under $OUTPUT_DIR"
