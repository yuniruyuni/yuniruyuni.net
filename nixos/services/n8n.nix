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
    # false にする理由 (一度 true で失敗している):
    #
    # モジュールは conmon + linger = true の組み合わせに警告を出す。当初これを
    # 「linger を使うなら healthy にできる」という助言と解釈して true にしたが、
    # 実際には unit が activating のままタイムアウトして failed になった。
    # コンテナ自体は起動して応答するのに systemd が READY を受け取れない。
    #
    # モジュールが認めている組み合わせは conmon + linger = false か
    # healthy + linger = true の 2 つ。healthy はコンテナ側の HEALTHCHECK が
    # 前提になるため、前者を採る。
    #
    # linger 無しでは podman が cgroup 管理を systemd から cgroupfs へ
    # フォールバックする警告を出すが、これは警告であって起動は妨げない。
    #
    # NixOS 26.05 の oci-containers は unit に常に Delegate=true を付けるように
    # なり、rootless で linger が無いと評価時に警告を出す (上流のテストは
    # conmon でも linger = true で回している)。Delegate=true の下でなら
    # conmon + linger = true でも READY が届く可能性はあるが、本番で確かめて
    # いないため、OS の更新とは切り離して別途試す。それまでは実績のある
    # false を維持し、この警告は意図したものとして受け入れる。
    linger = false;
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
        # Temporary, locally staged security rebuild; see docker/n8n-security and
        # docs/runbooks/n8n-runtime-security-2026-10.md. The application remains
        # 2.44.4; Node and its native modules are rebuilt against 26.12.1.
        image = "localhost/n8n-security:2.44.4-node26.12.1-security2";
        pull = "never";
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

  # 古い版の image を残さない。
  #
  # 更新のたびに新しい版を引くが、古いものは消えずに積み上がっていた。実測で
  # 23 個 × 約 1.7GB = 約 39GB。2 か月前の版まで残っており、ディスク使用の
  # 大半がこれだった。
  #
  # 世代を残さないのは、公開されている image なのでいつでも引き直せるから。
  # 手元に置いておく理由が無い。
  #
  # 起動した後に走らせる。先に消すと、これから使う版まで対象になる。
  # 稼働中のものは podman が拒むので、実際に消えるのは使っていない版だけ。
  # 停止時の exit 143 を成功として扱う。
  #
  # oci-containers の podman backend は conmon を main process にする
  # (Type=notify, --sdnotify=conmon)。`systemctl stop` で preStop の
  # `podman stop` がコンテナに SIGTERM を送ると、n8n (node) は 128+15 = 143 で
  # 終了し、conmon がその値で exit する。systemd は signal による終了なら
  # 成功扱いにするが、これは通常の exit code なので failed になる。
  #
  # 実際に 26.05 への switch では、switch 中に起動された n8n-backup が
  # バックアップのために podman-n8n を stop し、この 143 で failed になって
  # switch-to-configuration が exit 4 を返した。毎晩のバックアップでも
  # 同じ理由で failed が残る (apply-nixos.yml が reset-failed しているのは
  # このため)。
  #
  # oci-containers にはこれを指定するオプションが無く、生成される unit の
  # serviceConfig を直接足すのが想定された拡張方法 (モジュールのコメント参照)。
  # 動作中に外から SIGTERM で落とされた場合も成功扱いになり Restart=on-failure
  # が効かなくなるが、そのような停止経路はここには無い。
  systemd.services.podman-n8n.serviceConfig.SuccessExitStatus = [ 0 143 ];

  # Verify the staged image before creating the replacement container.
  # Staging instructions and the rollback archive are in the security runbook.
  systemd.services.podman-n8n.preStart = lib.mkBefore ''
    actual=$(${pkgs.podman}/bin/podman image inspect \
      localhost/n8n-security:2.44.4-node26.12.1-security2 --format '{{.Id}}')
    actual="''${actual#sha256:}"
    test "$actual" = "ca32ea47071c890793ef14a4f3baf9f6537a7df16dad01432e06afc9c35306ce"
  '';

  systemd.services.podman-n8n.serviceConfig.ExecStartPost = [
    ("-" + pkgs.writeShellScript "n8n-prune-old-images" ''
      set -u
      # 少し待つ。起動直後はまだコンテナが image を掴んでいない。
      sleep 20
      for id in $(${pkgs.podman}/bin/podman images --filter reference=n8nio/n8n -q | sort -u); do
        # 使われていれば podman が拒む。それでよい。
        ${pkgs.podman}/bin/podman rmi "$id" >/dev/null 2>&1 || true
      done
    '')
  ];

}
