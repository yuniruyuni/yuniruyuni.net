# Infrastructure

yuniruyuni.net のインフラストラクチャをTerraformで管理するリポジトリです。

## 構成

```
infrastructure/
├── bootstrap/     # GCS backend + Workload Identity (local backend)
├── cloudflare/    # Cloudflare DNS, Tunnel設定 (GCS backend)
├── gcp/           # 将来: Cloud Run等
└── scripts/       # ヘルパースクリプト
```

## セットアップ手順

### 1. GCPプロジェクト作成（手動）

```bash
# プロジェクト作成
gcloud projects create yuniruyuni-infrastructure --name="yuniruyuni Infrastructure"

# 課金アカウント紐付け
gcloud billing projects link yuniruyuni-infrastructure \
  --billing-account=YOUR_BILLING_ACCOUNT_ID
```

> **Note**: 必要なAPIの有効化はTerraformで自動的に行われます。

### 2. Bootstrap実行（local backend）

```bash
cd bootstrap

# ADC認証
gcloud auth application-default login

# Terraform実行
terraform init
terraform plan
terraform apply

# GitHub Secretsに登録する値を確認
terraform output github_secrets
```

### 3. GitHub Secrets登録

以下のSecretsをリポジトリに登録:

| Secret | 値 |
|--------|-----|
| `CLOUDFLARE_API_TOKEN` | Cloudflare API Token |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare Account ID |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | bootstrap outputの値 |
| `GCP_SERVICE_ACCOUNT` | bootstrap outputの値 |

### 4. Cloudflare API Token作成

Cloudflare Dashboard → My Profile → API Tokens で以下の権限を持つトークンを作成:

- Zone: Zone Settings (Read)
- Zone: DNS (Edit)
- Zone: Zone (Read)
- Account: Cloudflare Tunnel (Edit)

### 5. 既存リソースのImport

```bash
# 環境変数設定
export CLOUDFLARE_API_TOKEN="your-token"
export CLOUDFLARE_ZONE_ID="your-zone-id"
export CLOUDFLARE_ACCOUNT_ID="your-account-id"

# Importスクリプト実行
./scripts/import-cloudflare.sh

# 生成されたファイルを確認・編集後
cd cloudflare
terraform init
terraform plan
terraform apply
```

## CI/CD

- **PR時**: `terraform plan` が実行され、結果がPRにコメントされます
- **main merge時**: `terraform apply` が自動実行されます（production environment要承認）

## ローカル開発

```bash
cd cloudflare

# Terraform変数を環境変数で設定
export TF_VAR_cloudflare_api_token="your-token"
export TF_VAR_cloudflare_account_id="your-account-id"

# GCP認証（state読み書き用）
gcloud auth application-default login

terraform init
terraform plan
```
