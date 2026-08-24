# Agenix secrets configuration
# This file defines which age keys can decrypt which secrets
#
# To encrypt a secret:
#   cd nixos/secrets
#   nix run github:ryantm/agenix -- -e <secret-name>.age
#
# Or using EDITOR:
#   EDITOR=vim nix run github:ryantm/agenix -- -e <secret-name>.age
#
# To rekey all secrets (after changing keys):
#   nix run github:ryantm/agenix -- -r

let
  # VPS SSH host key (converted to age format)
  vps = "age1v35aw39m42una5eal8g6pfnuhm8kwc7q93c7v4zpyldfn8zjkp6sayqdkr";

  # 1Password infrastructure-admin key (disaster recovery, for rekeying when VPS changes)
  onepassword = "age1t5u8r467lwp2t5d0qjr38va4nmly3wyg5k9fwttaakmu66q4zyvqq58qav";

  # Systems that need to decrypt secrets at runtime
  systems = [ vps ];

  # Admins who can rekey secrets
  admins = [ onepassword ];
in
{
  # Cloudflared tunnel token
  "cloudflared-token.age".publicKeys = systems ++ admins;

  # n8n encryption key
  "n8n-encryption-key.age".publicKeys = systems ++ admins;

  # Mackerel API key
  "mackerel-api-key.age".publicKeys = systems ++ admins;

  # rclone config for Google Drive backup
  "rclone-config.age".publicKeys = systems ++ admins;

  # yunirun がアプリ側の秘密 (secrets/<ENV_NAME>.age) を復号するための age 秘密鍵。
  #
  # ホスト鍵 (vps) とは別に持つ。ホスト鍵は ssh のホスト鍵から導いているので
  # ホストを作り直すと変わるが、アプリのリポジトリにある暗号文は人が暗号化した
  # もので、鍵が変わると全アプリで暗号化し直しになる。
  #
  # 対応する公開鍵: age1uar0qhs2aev0s56rh6ckp6exrt76xk7revwpqfgtkwhgu9w4nu5q9eekgs
  "yunirun-secrets-key.age".publicKeys = systems ++ admins;

  # PostgreSQL DB passwords (per-app: owner + app user)
}
