# n8n October 2026 runtime security overlay

## 2026-10-29: 安定版 2.44.7 への更新候補

PR #266 が提案した 2.45.3 は公式の試験版のため採用しない。
同じ 2.44 系列の公式安定版 2.44.7 を使い、既存の署名済み Brotli
1.2.1-r0 対策、Node 26.12.1、rootless 実行、証明書検証を維持する。
以下の旧版手順は履歴であり、今回の固定値はこの節を優先する。

- 公式 base: `n8nio/n8n:2.44.7@sha256:942bc274709f27f99f7c6024a785d8e8f75ac06838cabcba448abb8d9127ec7b`
- amd64 manifest: `sha256:7a7708314f9b1d0656e2e7f697abb64fae5f76e1895f0a9ccb9036c3933a0394`
- 配備タグ: `localhost/n8n-security:2.44.7-brotli1.2.1-overlay1`
- rootless Podman が検査する config ID: `72e1babed6f96f68a93ebd34aa41fdee4011574cca6fd621a1e0913a73a52c7d`
- 検証済み Docker archive の SHA-256: `d2ebea30a2f87e9c9fd2ee9c17bcab4fe983b53b80ec9f17e2dd7890ace42605`
- 保持する旧版: `localhost/n8n-security:2.44.6-brotli1.2.1-overlay1`、config ID `60a5003bde5ec528b13daad0d017549869316fff0a66250e6557d3c60ef68a8b`
- 公開後3日の条件: GitHub Release の公開日時を基準に **2026-10-29 06:22 UTC 以降**。

公式 2.44.7 との差分は引き続き brotli-libs のみ。87 個のネイティブファイル、
7 個の信頼関連ファイル、404 個の DB 移行定義を保存する。旧 2.44.6 とも
ネイティブ・信頼関連・DB 移行定義は同一。既存のネイティブ・資格情報・
Code/HTTP ノード・公開 Webhook 検証はすべて実行し、版の期待値を更新した。
合成データによる 2.44.6 → 2.44.7 → 2.44.6 の試験では、資格情報1件と
ワークフロー2件（公開1件）を保持し、各段階で実行と SQLite quick_check が成功した。
実データの完全復元や外部 OAuth/業務フローを検証したとは扱わない。

上流の主な変更は IMAP 再接続、SharePoint、サブワークフロー失敗処理と
Python task runner の certifi 更新。今回のイメージには Python 実行環境と
別体 Python runner がないため、certifi 更新がこの稼働環境の CA 問題を
修正したとは主張しない。既存の Node/Brotli 対策は独立して維持する。

先に #261 の反映・正常性確認を終える。マージ前に、この exact archive を
既存の rootless Podman へ配置し、checksum/config ID と一時コンテナの動作を
確認する。**CI 成功だけでは本番ホストへの配置完了にならない。**
稼働版のイメージを保存し、直前の整合データバックアップ・復号検証を済ませる。
実行中ワークフローがあれば停止せず待つ。設定・権限や証明書検証は変更しない。
配備後は実 image/版、readiness、資格情報・ワークフロー数、公開状態、
全アプリ応答を確認する。旧版へ戻す場合も、新しいデータを黙って上書きしない。

As verified on 2026-10-25, n8n **2.44.6** is the latest official stable release;
2.45.3 is beta/next. The image now derives directly from official 2.44.6 and
changes only the separately vulnerable shared OS Brotli package. The official
Node 26.12.1, n8n, native modules, Git 2.55.0, Corepack 0.36.0, Yarn 1.22.22,
npm 11.21.1, user, entrypoint and runtime settings are preserved.

This supersedes the 2.44.4 security2 rebuild deployed through PR #253. That
rebuild remains a patched rollback candidate; the earlier security1 in PR #252
and unmodified 2.44.4 are not equivalent rollback targets.

## Provenance and trust

The Dockerfile pins official n8n 2.44.6 to index digest
`sha256:d02752c6ab446ae9db8deec2f9cc887c378f77cdcad31650814df936b7386dfb`.
The tested linux/amd64 manifest is
`sha256:845ac21710739d7206086974295f7f93932e0fa8dd87af6d9fb0b7aa0338ad15`.
Only linux/amd64 has been validated for this overlay.

Official Node 26.12.1 includes the decoder security backport. Its embedded
Brotli version string remains 1.2.0; that string alone is not a vulnerability
verdict. Node reports `node_shared_brotli=false`. The separate OS package in
the official image is brotli-libs 1.2.0-r1, whose decoder binary is identical
to the unpatched official 2.44.4 library. The actual shared consumer chain is
Git's git-remote-http -> libcurl -> libbrotlidec.

The sole replacement is the **official Alpine 3.24 signed binary package**
[brotli-libs 1.2.1-r0](https://dl-cdn.alpinelinux.org/alpine/v3.24/main/x86_64/brotli-libs-1.2.1-r0.apk),
SHA-256 `62a7e37e43bbfc1f8525a00ad2125fd5897135dc93b849733884cb78ffd8e26c`.
Its [official APKBUILD](https://github.com/alpinelinux/aports/blob/8313352127992a9d82e2c2024494f6c38a4dffb4/main/brotli/APKBUILD)
uses stable Brotli 1.2.1, upstream commit
`db24a98aed38a16de78cc05ca15cdd8dc2a0d92d`. That release includes backport
`b418fa81c48262a86a95332b0bc6d62c30aa78b6` of decoder fix
`0ed4268a4401abcb4472096340477cf4af7d1a2b`.

This is not a locally built or locally signed package. The signature is
`alpine-devel@lists.alpinelinux.org-6165ee59.rsa.pub`, already trusted by the
unmodified official n8n base. The existing key's SHA-256 is
`207e4696d3c05f7cb05966aee557307151f1f00217af4143c1bcaf33b8df733f`.
No signing credentials, keys, repositories or persistent trust are added.
Both the checksum and package signature are verified. Installation uses only
the base's existing trust store, with network disabled and repositories disabled.

A pinned Alpine stage supplies temporary installer/test tools through BuildKit
mounts. They, the APK archive and its build tools do not remain in the runtime.
The one new filesystem layer contains the shared libraries, accurate package
records/log and `/usr/local/share/runtime-security/brotli.txt`. Old 1.2.0 shared
objects are removed. Unlike security2, the installed APK database correctly
records **1.2.1-r0**. This one package comes from Alpine, rather than the base's
DHI build. Upstream image attestations describe the base, not this derived
artifact; scanners should inspect its actual package database and filesystem.
Do not claim this overlay has a vendor-issued whole-image attestation.

## Build and verification

```sh
docker build --platform linux/amd64 \
  -t localhost/n8n-security:2.44.6-brotli1.2.1-overlay1 docker/n8n-security

docker run --rm --network none --read-only --tmpfs /tmp:rw,nosuid,nodev,size=32m \
  --entrypoint node -v "$PWD/docker/n8n-security:/tests:ro" \
  localhost/n8n-security:2.44.6-brotli1.2.1-overlay1 /tests/native-smoke.cjs

docker run --rm --network none --entrypoint sh \
  -v "$PWD/docker/n8n-security:/tests:ro" \
  localhost/n8n-security:2.44.6-brotli1.2.1-overlay1 /tests/workflow-smoke.sh
```

The n8n Image CI workflow also compares official and candidate snapshots:
all official layers and runtime configuration remain; only brotli-libs changes
in the package inventory. Critical helpers, package trust, native modules and
migration files must have identical hashes. Local checks preserved 87 native
module files, eight critical files and seven trust/repository files. All 404
migration files also match security2's n8n 2.44.4.

Smoke tests exercise SQLite, isolated-vm, Kafka, Sentry and Snowflake musl
bindings; Node and shared-library Brotli roundtrips; shared decoder provenance
and Git/libcurl linkage; helper versions; fresh migrations; synthetic credential
encryption/decryption; local HTTP Request and Code nodes; and a published
webhook. They use disposable data and no external network. The webhook check
has a bounded registration wait, since readiness can precede webhook registration.

A separate disposable upgrade fixture verified that security2-created data and
credentials work in 2.44.6 and remain readable by security2 afterward. This is
bounded compatibility evidence, not permission to overwrite live data. Real
external OAuth flows and business workflows are not invoked by these tests.
Existing community modules should also be loaded against the candidate using
only a read-only mount of their installed code and no network or production
credential/database mount. Report pre-existing missing packages separately.

## Artifact staging and activation

The tested artifact uses tag
`localhost/n8n-security:2.44.6-brotli1.2.1-overlay1` and config ID
`60a5003bde5ec528b13daad0d017549869316fff0a66250e6557d3c60ef68a8b`.
Its local amd64 manifest is
`sha256:530c202843305c97c6297e4a1ce82715f0740382edf6885646ba5540bbda7ffb`;
the exported Docker archive SHA-256 is
`4ca96a0529f1a06ff80a811000c04e209c9778289bd9ffc7f413ad0d58ae9830`.
The NixOS preStart guard checks the config ID. Rebuilding may change the image
ID because of build timestamps and package logs: CI validates the recipe, while
activation deliberately selects the exact locally tested, staged artifact.

Use existing administrator SSH access. Preserve the running security2 image
as a checked OCI archive in an n8n-owned mode-0700 directory before staging;
for this rollout the directory is `/var/lib/n8n/security-rollback-20261025-overlay`.
Security2's config ID is
`ca32ea47071c890793ef14a4f3baf9f6537a7df16dad01432e06afc9c35306ce`.
Transfer the candidate with `docker save` into rootless `podman load`, then
verify its ID, runtime and shared decoder without activating it. No persistent
registry login is needed. The service retains `pull = "never"`; replacement
hosts must have this exact artifact staged before starting the configuration.

Merge only through the normal PR process after required checks and review.
The main branch requires one approving review; do not use owner override.
Recheck remote main, running image and service configuration before activation
to detect concurrent changes. Staging alone must leave active production intact.

Immediately before activation, briefly stop n8n and make a consistent encrypted
data archive in a new mode-0700 directory under `/var/lib/backups`, addressed
to existing host and infrastructure-admin recipients. Preserve the encrypted
n8n key and current NixOS configuration. Verify key recovery byte-for-byte
without printing secrets, and verify the archive decrypts and is readable.
Restart on every failure path. Do not use the general backup helper, which
also deletes old remote backups. Do not stop production merely to wait for review.

After normal NixOS deployment, verify the actual active image ID, n8n/Node,
shared decoder, helper commands, origin `/healthz/readiness`, workflow and
credential counts, and active workflow registration. Check all other application
HAProxy backends. Cloudflare HTTP 200 alone is insufficient. Never log credential
bodies, workflow content, keys or tokens.

## Rollback and overlay retirement

For image rollback, load the saved **security2** archive and revert the n8n image
and preStart ID through the normal configuration deployment. Preserve the current
data and encrypted snapshot. The disposable downgrade-read test passed, but a
production data restore overwrites newer data and requires a separate decision.
Do not fall back to unpatched vendor 2.44.4 or security1.

Remove this overlay when an official stable n8n image is verified to contain
both a patched Node runtime and a patched shared OS decoder, using actual
package provenance/library contents and the Git/libcurl linkage. Version labels
alone are insufficient when a vendor backports fixes. Repeat preservation,
native/community module and isolated workflow tests, pin the vendor digest,
then remove the Dockerfile and local artifact guard in the same reviewed change.

References: [Node advisory](https://nodejs.org/en/blog/vulnerability/october-2026-security-releases),
[official n8n 2.44.6 Dockerfile](https://github.com/n8n-io/n8n/blob/n8n%402.44.6/docker/images/n8n/Dockerfile),
[official Node backport](https://github.com/nodejs/node/blob/v26.12.1/deps/brotli/c/dec/decode.c),
[Brotli 1.2.1 release](https://github.com/google/brotli/releases/tag/v1.2.1).
