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

以下のSecretsをEnvironmentレベルに登録:

| Secret | 説明 | Environment |
|--------|------|-------------|
| `CLOUDFLARE_API_TOKEN` | Cloudflare API Token | plan, apply |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare Account ID | plan, apply |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | bootstrap outputの値 | plan, apply |
| `GCP_SERVICE_ACCOUNT` | bootstrap outputの値 | plan, apply |
| `VPS_IP_ADDRESS` | VPSのIPアドレス | plan, apply |
| `GCP_PROJECT_ID` | GCPプロジェクトID | plan, apply |
| `SSH_PRIVATE_KEY` | VPS SSH秘密鍵 (Ed25519) | apply |

## CI/CD

| ワークフロー | トリガー | 内容 |
|--------------|----------|------|
| `validate-terraform` | PR (`*.tf`, `*-terraform*.yml`) | `terraform fmt -check` + `terraform validate` |
| `plan-terraform` | PR (`*.tf`, `*-terraform*.yml`) | `terraform plan` → PRコメント (フォークPRはスキップ) |
| `trigger-plan` | PRコメント `/plan` | Write権限者がフォークPRのplanを手動トリガー |
| `apply-terraform` | main push (`*.tf`) | `terraform apply` (apply environment) |
| `apply-nixos` | main push (`nixos/**`) | NixOS構成をVPSにデプロイ (apply environment) |

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
