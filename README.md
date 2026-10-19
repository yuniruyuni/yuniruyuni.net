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
├── docs/                # 運用手順（アプリ追加、DB password rotation、agenix rekey）
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

## CI/CD

| ワークフロー | トリガー | 内容 |
|--------------|----------|------|
| `validate-terraform` | PR / main push (`*.tf`, `*-terraform*.yml`) | `terraform fmt -check` + `terraform validate` |
| `plan-terraform` | PR (`*.tf`, `*-terraform*.yml`) | `terraform plan` → PRコメント (plan environment の承認が必要。フォークPRは job ごとスキップ。同じ commit で再実行するときは Actions の Re-run) |
| `apply-terraform` | main push (`*.tf`) | `terraform apply` (apply environment) |
| `validate-nixos` | PR / main push (`nixos/**`) | `nix flake check` + NixOS構成ビルド |
| `apply-nixos` | main push (`nixos/**`) | NixOS構成をVPSにデプロイ (apply environment) |
| `uptime` | schedule (10分毎) / 手動 | VPS の外から公開ホスト名を死活監視し、落ちたら `outage` issue を開く ([外形監視](#外形監視-uptime)) |

GCP の CI SA は Workload Identity の `sub` (immutable subject claim) で environment ごとに束縛している: apply SA は `environment: apply` の job だけ、plan SA は `environment: plan` の job だけが借りられる (`ci.tf`)。workflow の `environment:` を変えるときは `ci.tf` も同時に直すこと。

`main` は GitHub ruleset で保護し、PR 経由と 1 approval を要求する。単独管理リポジトリのため owner は PR ruleset を bypass できる。`apply` environment は `main` ブランチからのデプロイのみ許可し、merge 後の追加 reviewer 承認は要求しない。

## 外形監視 (uptime)

Grafana → n8n のアラートは VPS 上で動くため、VPS ごと落ちると通知も届かない。
`.github/workflows/uptime.yml` が GitHub Actions 上 (VPS の外) から 10 分おきに
`scripts/uptime-probe.sh` の各ターゲットを叩いて補う。

- **判定**: 期待ステータスと本文の文字列の両方を見る (SPA の fallback や Cloudflare のエラーページを健康と取り違えないため)。
  各アプリは `/health` (`{"status":"ok"}`)、`/health` を持たない lom はトップページ、
  n8n は Access を bypass している `/webhook/*` に未登録の webhook を投げて n8n 自身の 404 を確認する。
  失敗は 20 秒おきに 3 回まで再試行してから落ちたとみなす
- **通知**: 落ちると `outage` ラベルの issue が開き (owner を mention)、全部戻ると自動で close される。
  状態が変わった run (新規に落ちた / 落ちている集合が変わった) だけ job が失敗するので、
  scheduled workflow の失敗メールも届く。落ち続けている間は 10 分ごとには鳴らない
- **落ちたら**: issue の表で落ちたホスト名を確認。全滅なら VPS / cloudflared (`530`)、
  一部ならそのアプリ (`502` は HAProxy の裏が全滅) を疑う。復旧すれば次の run で issue が閉じる
- **ターゲットの追加**: tunnel の ingress (`cloudflare.tf`) にホスト名を足したら `scripts/uptime-probe.sh` の `TARGETS` にも足す
- **注意**: Actions の schedule は混雑時に数分〜十数分遅れることがある。また public リポジトリでは
  60 日間リポジトリに活動が無いと scheduled workflow が自動で無効化される (事前にメールが来る)。
  Renovate の PR が定期的に入るので通常は該当しないが、無効化されたら Actions タブから再度有効化する
- Cloudflare の Health Checks は Pro 以上のゾーン向けで、このゾーン (Free) では使えない

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

## 運用ドキュメント

- [Cloud Run App 追加手順](docs/add-app.md)
- [DB Password Rotation 手順](docs/db-password-rotation.md)
- [Agenix Secrets Rekey 手順](docs/agenix-rekey.md)
