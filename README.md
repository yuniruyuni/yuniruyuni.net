# yuniruyuni.net

yuniruyuni.net のインフラストラクチャを管理するリポジトリです。

- **Terraform**: Cloudflare DNS/Tunnel、GCP (Cloud Run, GCE, Workload Identity) を管理
- **NixOS**: VPSの構成管理 (Nix Flakes, agenix)

## 構成

```
.
├── *.tf                 # Terraform設定（ルート直下、state / CI SA / WIF も含め全てここで管理）
├── scripts/             # ヘルパースクリプト
│   └── bootstrap.sh     # 新規環境用: gcloudで最小限を作ってtf stateに取り込む (idempotent)
├── nixos/               # NixOS VPS構成 (Flakes + agenix)
│   ├── secrets/         # agenix暗号化シークレット
│   └── services/        # サービス定義 (cloudflared, n8n, etc.)
├── ssh/                 # SSH known_hosts
└── .github/workflows/   # CI/CD
```

## GitHub Secrets

以下のSecretsをEnvironmentレベルに登録:

| Secret | 説明 | plan | apply |
|--------|------|------|-------|
| `CLOUDFLARE_API_TOKEN` | Cloudflare API Token | 読み取り専用トークン | 読み書きトークン |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare Account ID | 共通値 | 共通値 |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | `terraform output ci_workload_identity_provider` | 共通値 | 共通値 |
| `GCP_SERVICE_ACCOUNT` | `terraform output ci_plan_service_account` / `ci_apply_service_account` | plan SA (`terraform-github-plan`) | apply SA (`terraform-github`) |
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

## 新規環境セットアップ / DR

```bash
# 1. GCP認証（プロジェクトのOwner相当）
gcloud auth login
gcloud auth application-default login
gcloud config set project yuniruyuni-net

# 2. 最小限のGCPリソース作成 + terraform stateへ取り込み (idempotent)
PROJECT=yuniruyuni-net GITHUB_ORG=yuniruyuni GITHUB_REPO=yuniruyuni.net \
  scripts/bootstrap.sh

# 3. スクリプト末尾に表示される値を GitHub Environment (plan / apply) に登録:
#    GCP_PROJECT_ID / GCP_WORKLOAD_IDENTITY_PROVIDER / GCP_SERVICE_ACCOUNT

# 4. main にpushすると CI が残りのリソースを apply
```

## ローカル開発 (plan確認など)

```bash
gcloud auth application-default login

export TF_VAR_cloudflare_api_token="your-token"
export TF_VAR_cloudflare_account_id="your-account-id"
export TF_VAR_vps_ip_address="your-vps-ip"
export TF_VAR_gcp_project_id="your-project-id"
export TF_VAR_owner_email="your-email"
export TF_VAR_google_oauth_client_id="..."
export TF_VAR_google_oauth_client_secret="..."

terraform init
terraform plan
```
