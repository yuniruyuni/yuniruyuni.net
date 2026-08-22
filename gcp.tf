# =============================================================================
# GCP Provider
# =============================================================================

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

# =============================================================================
# Enable Required APIs
# =============================================================================

# 2026-08-22 に Cloud Run 一式を撤去した。全 7 アプリが VPS 上の yunirun へ
# 移り、GCP に置く必要のあるものが Terraform の state 置き場と、その CI が
# 使う Workload Identity (ci.tf) だけになったため。
#
# ここから外したのは run / compute / artifactregistry / containeranalysis /
# cloudscheduler。disable_on_destroy = false なので、一覧から外しても API
# 自体は有効なまま残る。Google OAuth のクライアント (Cloudflare Access の
# ID プロバイダと StreamerPost のログイン) はこのプロジェクトにあるが、
# Terraform の管理外なのでリソースの削除では消えない。
locals {
  required_apis = toset([
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "secretmanager.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "storage.googleapis.com",              # state bucket + SM usage
    "cloudresourcemanager.googleapis.com", # project-level IAM management
  ])
}

resource "google_project_service" "required" {
  for_each           = local.required_apis
  service            = each.value
  disable_on_destroy = false
}

# NOTE: アプリの秘密は agenix が持つ。VPS 上のアプリで秘密が要る場合は、
# 各リポジトリの yunirun.jsonc の secrets で agenix の秘密名を指し、
# nixos/secrets.nix 側でその秘密を定義する。DB のパスワードは yunirun が
# 自分の金庫 (ホスト鍵と管理者鍵で暗号化) に持つ。
