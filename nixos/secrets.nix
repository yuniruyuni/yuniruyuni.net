# Secrets configuration using agenix
# Secrets are encrypted with age and decrypted at runtime
#
# Note: PostgreSQL DB password secrets are defined in services/postgresql.nix
# (auto-derived from dbApps list)

{ config, ... }:

{
  # Define secrets - these will be decrypted to /run/agenix/
  age.secrets = {
    cloudflared-token = {
      file = ./secrets/cloudflared-token.age;
      owner = "cloudflared";
      group = "cloudflared";
      mode = "0400";
    };

    # n8n は rootless podman で動くため、サービスを動かすユーザが読める
    # 必要がある。root 所有のままだと podman が起動時に
    # "permission denied" で落ちる。
    n8n-encryption-key = {
      file = ./secrets/n8n-encryption-key.age;
      owner = "n8n";
      group = "n8n";
      mode = "0400";
    };

    mackerel-api-key = {
      file = ./secrets/mackerel-api-key.age;
      owner = "mackerel-agent";
      group = "mackerel-agent";
      mode = "0400";
    };

    # yunirun がアプリ側の秘密 (secrets/<ENV_NAME>.age) を復号する age 秘密鍵。
    #
    # 読むのは converge (root) だけ。ホスト鍵とは別に持つ理由は
    # secrets/secrets.nix に書いてある。
    yunirun-secrets-key = {
      file = ./secrets/yunirun-secrets-key.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };

    rclone-config = {
      file = ./secrets/rclone-config.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };
  };
}
