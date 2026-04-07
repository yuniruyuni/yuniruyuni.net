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

  # PostgreSQL DB passwords (per-app: owner + app user)
  "db-password-stream_tag_inventory.age".publicKeys = systems ++ admins;
  "db-password-stream_tag_inventory_app.age".publicKeys = systems ++ admins;
  "db-password-template.age".publicKeys = systems ++ admins;
  "db-password-template_app.age".publicKeys = systems ++ admins;
}
