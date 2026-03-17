# yuniruyuni.net

yuniruyuni.net のインフラストラクチャを管理するリポジトリです。

- **Terraform**: Cloudflare DNS/Tunnel、GCP (Cloud Run, GCE, Workload Identity) を管理
- **NixOS**: VPSの構成管理 (Nix Flakes, agenix)

## 構成

```
.
├── *.tf                 # Terraform設定（ルート直下）
├── bootstrap/           # GCS backend + Workload Identity (local backend)
├── nixos/               # NixOS VPS構成 (Flakes + agenix)
│   ├── secrets/         # agenix暗号化シークレット
│   └── services/        # サービス定義 (cloudflared, n8n, etc.)
├── scripts/             # ヘルパースクリプト
├── ssh/                 # SSH known_hosts
└── .github/workflows/   # CI/CD
```

## GitHub Secrets

以下のSecretsをリポジトリに登録:

| Secret | 説明 | Environment |
|--------|------|-------------|
| `CLOUDFLARE_API_TOKEN` | Cloudflare API Token | terraform-plan, production |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare Account ID | terraform-plan, production |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | bootstrap outputの値 | terraform-plan, production |
| `GCP_SERVICE_ACCOUNT` | bootstrap outputの値 | terraform-plan, production |
| `VPS_IP_ADDRESS` | VPSのIPアドレス | terraform-plan, production |
| `GCP_PROJECT_ID` | GCPプロジェクトID | terraform-plan, production |
| `SSH_PRIVATE_KEY` | VPS SSH秘密鍵 (Ed25519) | production |

## CI/CD

| ワークフロー | トリガー | 内容 |
|--------------|----------|------|
| `terraform-validate` | PR (`*.tf`, `terraform-*.yml`) | `terraform fmt -check` + `terraform validate` |
| `terraform-plan` | PR (`*.tf`, `terraform-*.yml`) | `terraform plan` → PRコメント (フォークPRはスキップ) |
| `terraform-plan-comment` | PRコメント `/plan` | Write権限者がフォークPRのplanを手動トリガー |
| `terraform-apply` | main push (`*.tf`) | `terraform apply` (production environment) |
| `nixos-deploy` | main push (`nixos/**`) | NixOS構成をVPSにデプロイ |

## ローカル開発

```bash
# GCP認証（state読み書き用）
gcloud auth application-default login

# Terraform変数を環境変数で設定
export TF_VAR_cloudflare_api_token="your-token"
export TF_VAR_cloudflare_account_id="your-account-id"
export TF_VAR_vps_ip_address="your-vps-ip"
export TF_VAR_gcp_project_id="your-project-id"

terraform init
terraform plan
```
