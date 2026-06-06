# Cloud Run App 追加手順

このリポジトリは Cloud Run サービス本体を作成しません。各アプリ repository が Cloud Run サービスとコンテナ image を管理し、このリポジトリは共通基盤、DNS、Cloudflare Tunnel、Secret Manager の access control を管理します。

## 前提

- Cloud Run サービスはアプリ repository 側で先に作成する。
- Cloud Run ingress は `internal` または `internal-and-cloud-load-balancing` にする。
- この repository は `allUsers` invoker を付与するため、公開 ingress の Cloud Run サービスは Terraform の precondition で拒否される。

## Terraform 側

1. `gcp.tf` の `local.cloud_run_services` に追加する。

   ```hcl
   new_app = { name = "new-app", hostname = "new-app" }
   ```

   `hostname = ""` は root domain を意味するため、通常のサブドメインでは使わない。

2. DB が必要なアプリは `gcp.tf` の `local.db_apps` にも追加する。

   ```hcl
   new_app = {
     service_name = "new-app"
   }
   ```

3. `cloudflare.tf` の `local.dns_records` に、GCE tunnel 向け CNAME を追加する。

   ```hcl
   new_app = { name = "new-app", type = "CNAME", target = "tunnel_gce", proxied = true }
   ```

4. Terraform PR を作成し、plan で次を確認する。

   - Cloudflare DNS record が追加される。
   - GCE tunnel config に hostname が追加される。
   - DB アプリの場合は Secret Manager secret と IAM binding が追加される。

5. アプリ固有の runtime secret が必要な場合は `gcp.tf` の `local.runtime_secrets` に追加する。

   ```hcl
   new_app_api_key = {
     secret_id = "new-app-api-key"
     service   = "new_app"
   }
   ```

   Terraform は Secret Manager の secret resource と Cloud Run service account への
   `secretAccessor` だけを管理する。secret value は Terraform state に入れず、
   手動で version を投入する。

   Browser session や overlay URL token のような app runtime secret も同じ
   `local.runtime_secrets` に追加する。

## NixOS / PostgreSQL 側

DB が必要なアプリだけ実施する。

1. `nixos/services/postgresql.nix` の `dbApps` に追加する。

   ```nix
   { name = "new_app"; pgschemaManagesGrants = true; }
   ```

   PostgreSQL database/user 名は `-` ではなく `_` を使う。

2. agenix secret を2つ作る。

   ```bash
   cd nixos/secrets
   nix run github:ryantm/agenix -- -e db-password-new_app.age
   nix run github:ryantm/agenix -- -e db-password-new_app_app.age
   ```

3. `nixos/secrets/secrets.nix` に公開鍵設定を追加する。

   ```nix
   "db-password-new_app.age".publicKeys = systems ++ admins;
   "db-password-new_app_app.age".publicKeys = systems ++ admins;
   ```

4. アプリ repository 側の Secret Manager 参照名と DB 接続設定を合わせる。

   - owner/migration password: `new-app-db-password`
   - app password: `new-app-db-app-password`
   - Cloudflare Access service token: `cf-db-access-client-id` / `cf-db-access-client-secret`

## デプロイ順

1. アプリ repository で Cloud Run サービスを作成し、restricted ingress にする。
   Terraform は `data.google_cloud_run_service.services` で service を読むため、
   この bootstrap service が無い状態では plan/apply できない。アプリ側に
   `cloudrun-bootstrap.yaml` や bootstrap workflow がある場合はそれを先に実行する。
2. この repository の Terraform PR を merge して DNS/Tunnel/Secret access を反映する。
3. DB が必要な場合、この repository の NixOS 変更を merge して PostgreSQL database/user を反映する。
4. Secret Manager の secret version を投入する。
5. アプリ repository で DB 接続設定を有効化して deploy する。
