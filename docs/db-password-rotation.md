# DB Password Rotation 手順

PostgreSQL password は VPS 側の agenix secret と GCP Secret Manager の両方に存在します。値がずれると Cloud Run アプリが DB に接続できなくなるため、rotation は同じ値を両方へ反映します。

## 対象

アプリごとに2つの password がある。

- owner/migration user: `${app}`
- application user: `${app}_app`

例: `stream_tag_inventory`

- `nixos/secrets/db-password-stream_tag_inventory.age`
- `nixos/secrets/db-password-stream_tag_inventory_app.age`
- GCP Secret Manager: `stream-tag-inventory-db-password`
- GCP Secret Manager: `stream-tag-inventory-db-app-password`

## 手順

1. 新しい password を生成する。

   ```bash
   openssl rand -base64 32
   ```

2. agenix secret を更新する。

   ```bash
   cd nixos/secrets
   nix run github:ryantm/agenix -- -e db-password-<app>.age
   nix run github:ryantm/agenix -- -e db-password-<app>_app.age
   ```

3. GCP Secret Manager に同じ値の新 version を追加する。

   ```bash
   printf '%s' "$OWNER_PASSWORD" | gcloud secrets versions add <service-name>-db-password --data-file=-
   printf '%s' "$APP_PASSWORD" | gcloud secrets versions add <service-name>-db-app-password --data-file=-
   ```

4. NixOS 変更を merge して deploy する。

   `postgresql-app-credentials.service` が `ALTER USER` を実行し、VPS PostgreSQL 側の password を更新する。

5. アプリ repository を redeploy する。

   Cloud Run が Secret Manager の latest version を読む構成の場合でも、環境変数や mounted secret の反映には revision 更新が必要になることがある。

6. 接続確認後、古い Secret Manager version を disable する。

   ```bash
   gcloud secrets versions list <service-name>-db-password
   gcloud secrets versions disable <old-version> --secret=<service-name>-db-password
   ```

## 注意

- owner/migration user と app user の password は混ぜない。
- `pgschemaManagesGrants = true` のアプリでは table grant はアプリ migration 側が管理する。NixOS 側では CONNECT と schema USAGE だけを付与する。
- rotation 中は、GCP Secret Manager と VPS PostgreSQL の値が一時的にずれる。NixOS deploy とアプリ redeploy は同じ作業枠で実施する。
