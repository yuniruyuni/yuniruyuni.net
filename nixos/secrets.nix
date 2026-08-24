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

    # StreamerPost が使う秘密。yunirun が /run/agenix から読んでコンテナへ
    # 環境変数として渡す (アプリ側の yunirun.jsonc が対応を宣言する)。
    #
    # owner を root にしているのは、読むのが converge (root) だけだから。
    # コンテナへは yunirun が tmpfs 上の env ファイル経由で渡すので、
    # アプリのユーザがこのファイルを直接読む必要はない。
    streamer-post-better-auth-secret = {
      file = ./secrets/streamer-post-better-auth-secret.age;
      owner = "root";
      mode = "0400";
    };
    streamer-post-allowed-emails = {
      file = ./secrets/streamer-post-allowed-emails.age;
      owner = "root";
      mode = "0400";
    };
    streamer-post-twitch-client-secret = {
      file = ./secrets/streamer-post-twitch-client-secret.age;
      owner = "root";
      mode = "0400";
    };
    streamer-post-google-client-secret = {
      file = ./secrets/streamer-post-google-client-secret.age;
      owner = "root";
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
