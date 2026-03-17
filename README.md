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

| Secret | 説明 | plan | apply |
|--------|------|------|-------|
| `CLOUDFLARE_API_TOKEN` | Cloudflare API Token | 読み取り専用トークン | 読み書きトークン |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare Account ID | 共通値 | 共通値 |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | bootstrap outputの値 | 共通値 | 共通値 |
| `GCP_SERVICE_ACCOUNT` | bootstrap outputの値 | `terraform-github-plan` (読み取り専用) | `terraform-github` (読み書き) |
| `VPS_IP_ADDRESS` | VPSのIPアドレス | 共通値 | 共通値 |
| `GCP_PROJECT_ID` | GCPプロジェクトID | 共通値 | 共通値 |
| `SSH_PRIVATE_KEY` | VPS SSH秘密鍵 (Ed25519) | — | 設定 |

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
