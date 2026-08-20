# n8n service configuration
#
# rootless podman で動かす。以前は oci-containers の既定 (podman.user = "root")
# だったため root の system service として動いており、コンテナ内 uid 1000 が
# ホストの yuniruyuni (wheel + passwordless sudo) と同一だった。コンテナから
# 脱出できればそのまま sudo が使え、root 経由で peer 認証により Postgres の
# superuser まで到達できる状態になっていた。
#
# n8n は webhook パスが Cloudflare Access の bypass で公開されており、かつ
# ワークフロー実行が本業＝設計上コード実行できるサービスなので、この経路は
# 塞いでおく価値が大きい。
#
# 専用ユーザ n8n で rootless 化することで、脱出しても届く先が sudo を持たない
# システムユーザに限定される。
#
# Secrets managed by agenix

{ config, pkgs, lib, ... }:

{
  # n8n 専用のシステムユーザ。
  #
  # yuniruyuni ではなく専用ユーザにするのが要点。yuniruyuni は wheel かつ
  # passwordless sudo なので、そのユーザで rootless 化しても昇格経路が残る。
  users.users.n8n = {
    isSystemUser = true;
    group = "n8n";
    home = "/var/lib/n8n";
    createHome = true;

    # rootless podman が使う subuid/subgid を自動割り当てする。
    autoSubUidGidRange = true;

    # 明示が必要。既定値は null で、oci-containers が `&& linger` と評価するため
    # 未設定だと Nix の型エラーになる。
    #
    # true にする理由: 最初 false で試したところ podman が起動時に
    #   "The cgroupv2 manager is set to systemd but there is no systemd user
    #    session available" / "enable lingering with: loginctl enable-linger"
    # と警告し、cgroupfs へフォールバックした。systemd cgroup 管理下に置くには
    # lingering が要る。
    #
    # モジュールは conmon + linger = true の組み合わせに警告を出すが、
    # これは "linger を使うなら sdnotify = healthy にできる" という助言であって
    # エラーではない。healthy はコンテナ側のヘルスチェック定義が前提になり、
    # n8n の image が HEALTHCHECK を持つか不明なので conmon のままにする。
    linger = true;
  };
  users.groups.n8n = { };

  # データディレクトリ。
  #
  # Z で再帰的に所有者だけを移す。モードは `-` にして既存のファイルモードを
  # 保つ (0700 を再帰適用すると全ファイルが実行可能になってしまう)。
  systemd.tmpfiles.rules = lib.mkAfter [
    "d /var/lib/n8n 0700 n8n n8n -"
    "Z /var/lib/n8n/data - n8n n8n -"
  ];

  # n8n container service using Podman
  virtualisation.oci-containers = {
    backend = "podman";
    containers = {
      n8n = {
        image = "n8nio/n8n:2.34.1";
        autoStart = true;
        ports = [ "127.0.0.1:5678:5678" ];
        volumes = [
          "/var/lib/n8n/data:/home/node/.n8n"
        ];
        environment = {
          GENERIC_TIMEZONE = "Asia/Tokyo";
          TZ = "Asia/Tokyo";
          WEBHOOK_URL = "https://n8n.yuniruyuni.net";
        };
        # Use agenix-managed secret
        environmentFiles = [
          config.age.secrets.n8n-encryption-key.path
        ];

        # systemd サービスをこのユーザで動かす = rootless podman になる。
        podman.user = "n8n";

        extraOptions = [
          "--user=1000:1000" # コンテナ内の node ユーザ

          # ホストの n8n ユーザをコンテナ内の uid 1000 へ写像する。
          #
          # これが無いと、rootless の user namespace ではコンテナ内 uid 1000 が
          # ホストの subuid (100000 番台) に写像され、n8n 所有の
          # /var/lib/n8n/data へ書き込めなくなる。
          "--userns=keep-id:uid=1000,gid=1000"
        ];
      };
    };
  };

}
