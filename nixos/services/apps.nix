# VPS 上で動かすアプリケーション
#
# 1 アプリ = 1 エントリ。ここに足すと deploy ユーザ・コンテナ・HAProxy の
# backend・opkssh の認可がまとめて生成される。
#
# ■ 全体の流れ
#
#   GitHub Actions (アプリ repo)
#     → opkssh で短命 SSH 証明書を取得
#     → deploy-<name> として ssh、app-deploy を実行 (それ以外は何もできない)
#     → GHCR から image を pull し、blue/green を順に入れ替え
#     → HAProxy がヘルスチェックで自動的に振り分けを追従
#
# ■ 無停止の実現方法
#
# HAProxy の裏に同じアプリを 2 つ (blue/green) 置き、片方ずつ再起動する。
# 再起動中の系はヘルスチェックが落ちるので HAProxy が自動的に外し、もう片方へ
# 流す。HAProxy の admin socket を使った明示的な切り替えは行わない。
# socket の権限をアプリ間で共有せずに済み、状態を持たない分こわれにくい。
#
# 入れ替え中は新旧が短時間混在する。厳密なアトミック切り替えが要る場合は
# admin socket 経由の drain へ移行する余地を残してある。
#
# ■ ネットワーク分離
#
# コンテナは独立した netns に置き、HTTP だけを 127.0.0.1 に publish する。
# PostgreSQL へは TCP ではなく Unix ソケット (/run/postgresql) の bind mount で
# 到達させる。こうすると、コンテナからはホストの loopback 上の他サービス
# (n8n など) には一切届かない。
#
# Network=host なら手っ取り早いが、それだとホストの loopback 全体が見えて
# しまうため採らない。

{ config, pkgs, lib, ... }:

let
  apps = {
    template = {
      # Quadlet の unit を /etc/containers/systemd/users/<uid>/ に置くため、
      # uid は eval 時に確定している必要がある。動的割り当てだと使えない。
      uid = 988;

      # opkssh の認可に使う。sub は repo:<repo>:ref:refs/heads/main になる。
      repo = "yuniruyuni/template";
      image = "ghcr.io/yuniruyuni/template";

      # HAProxy が listen するポート (cloudflared の向き先)
      frontendPort = 8100;
      # blue/green それぞれのアプリが listen するポート
      colorPorts = {
        blue = 8101;
        green = 8102;
      };

      healthPath = "/health";

      db = {
        user = "template_app";
        name = "template";
        secret = "db-password-template_app";
      };
    };
  };

  colors = [ "blue" "green" ];

  deployUser = name: "deploy-${name}";

  # コンテナが参照するローカルタグ。app-deploy が pull した image をこの名前に
  # 付け替えることで、unit 側は静的なまま中身だけ入れ替わる。
  localTag = name: "localhost/${name}:current";

  mkContainerFile = name: app: color:
    pkgs.writeText "${name}-${color}.container" ''
      [Unit]
      Description=${name} (${color})

      [Container]
      Image=${localTag name}
      # blue/green は PORT だけが違う。PublishPort は使わず、アプリ自身に
      # 別ポートを listen させる… のではなく netns 内は同じ 3000 のままにして
      # ホスト側の公開ポートで分ける。
      PublishPort=127.0.0.1:${toString app.colorPorts.${color}}:3000
      Environment=PORT=3000
      Environment=STATIC_DIR=./static

      # PostgreSQL へは Unix ソケットで繋ぐ。TCP を使わないので、この
      # コンテナからホストの loopback 上の他サービスへは到達できない。
      Volume=/run/postgresql:/run/postgresql
      Environment=PGHOST=/run/postgresql
      Environment=PGPORT=5432
      Environment=DB_USER=${app.db.user}
      Environment=DB_NAME=${app.db.name}

      # 値は podman secret 経由で /run/agenix から実行時に取得される。
      # ディスクにも unit ファイルにも秘密は現れない (services/podman-secrets.nix)。
      Secret=${app.db.secret},type=env,target=DB_PASSWORD

      [Service]
      Restart=always
      # image がまだ無い初回は起動できないので、失敗しても諦めずに待つ。
      RestartSec=10

      [Install]
      WantedBy=default.target
    '';

  # deploy ユーザが実行できる唯一のコマンド。
  #
  # GHCR の認証情報は stdin で受け取る。GitHub Actions の GITHUB_TOKEN を
  # そのまま渡す想定で、job の終了とともに失効するため VPS 側に長期の
  # 資格情報を置かずに済む。authfile は tmpfs に置き、使用後に消す。
  mkDeployScript = name: app:
    pkgs.writeShellScriptBin "app-deploy" ''
      set -euo pipefail

      if [ $# -ne 1 ]; then
        echo "usage: app-deploy <image-tag>   (GHCR token on stdin)" >&2
        exit 1
      fi
      tag="$1"

      case "$tag" in
        "" | *[!A-Za-z0-9._-]* )
          echo "app-deploy: invalid image tag: $tag" >&2
          exit 1
          ;;
      esac

      runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
      authfile="$runtime_dir/ghcr-auth.json"
      cleanup() { rm -f "$authfile"; }
      trap cleanup EXIT

      echo "==> logging in to ghcr.io"
      ${pkgs.podman}/bin/podman login ghcr.io \
        --username "$(echo "${app.repo}" | cut -d/ -f1)" \
        --password-stdin \
        --authfile "$authfile" >/dev/null

      echo "==> pulling ${app.image}:$tag"
      ${pkgs.podman}/bin/podman pull --authfile "$authfile" "${app.image}:$tag"
      ${pkgs.podman}/bin/podman tag "${app.image}:$tag" "${localTag name}"

      # blue/green を順に入れ替える。片方を落としている間はもう片方が
      # 受けるので、HAProxy 越しには停止しない。
      ${lib.concatMapStringsSep "\n" (color: ''
        echo "==> restarting ${color}"
        systemctl --user restart ${name}-${color}.service

        echo "==> waiting for ${color} to become healthy"
        ok=0
        for _ in $(seq 1 60); do
          if ${pkgs.curl}/bin/curl -fsS --max-time 3 \
               "http://127.0.0.1:${toString app.colorPorts.${color}}${app.healthPath}" >/dev/null 2>&1; then
            ok=1
            break
          fi
          sleep 2
        done
        if [ "$ok" -ne 1 ]; then
          echo "app-deploy: ${color} did not become healthy; aborting before touching the other side" >&2
          ${pkgs.systemd}/bin/journalctl --user -u ${name}-${color}.service -n 40 --no-pager >&2 || true
          exit 1
        fi
      '') colors}

      echo "==> done: ${app.image}:$tag"
    '';

  # agenix の秘密を podman secret として登録し直す。
  #
  # podman secret 側に値は保持されておらず (services/podman-secrets.nix)、
  # 保持しているのは「どの agenix secret を指すか」という対応付けだけなので、
  # 起動のたびに張り直しても情報は増えない。
  #
  # systemd.user.services は全ユーザの systemd インスタンスに配られてしまうため
  # 使わない。User= を指定した system サービスにして deploy ユーザに限定する。
  mkSecretLinkScript = name: app: pkgs.writeShellScript "link-${name}-secrets" ''
    set -eu
    ${pkgs.podman}/bin/podman secret rm ${app.db.secret} >/dev/null 2>&1 || true
    printf '%s' '${app.db.secret}' \
      | ${pkgs.podman}/bin/podman secret create ${app.db.secret} - >/dev/null
  '';

  mkSecretLinkService = name: app: {
    description = "Link agenix secrets into podman for ${name}";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = deployUser name;
      Group = deployUser name;
      # uid は動的に割り当てられるため eval 時には確定しない。systemd の
      # 指定子 %U を使って実行時に解決させる。
      Environment = [
        "HOME=/var/lib/${deployUser name}"
        "XDG_RUNTIME_DIR=/run/user/%U"
      ];
      ExecStart = "${mkSecretLinkScript name app}";
    };
  };
in
{
  # deploy ユーザ。wheel には入れない = sudo を持たない。
  users.users = lib.mapAttrs' (name: app:
    lib.nameValuePair (deployUser name) {
      isSystemUser = true;
      uid = app.uid;
      group = deployUser name;
      home = "/var/lib/${deployUser name}";
      createHome = true;
      # rootless podman が使う subuid/subgid
      autoSubUidGidRange = true;
      # ログインセッションが無くてもコンテナを動かし続けるために必要
      linger = true;
      # ssh からコマンドを実行させるためシェルが要る
      shell = pkgs.bashInteractive;
    }) apps;

  users.groups = lib.mapAttrs' (name: app:
    lib.nameValuePair (deployUser name) { gid = app.uid; }) apps;

  # DB パスワードは postgres (postgresql-app-credentials が User=postgres で読む) と
  # deploy ユーザの両方が読む必要があるので、group を広げる。
  age.secrets = lib.mapAttrs' (name: app:
    lib.nameValuePair app.db.secret {
      group = lib.mkForce (deployUser name);
      mode = lib.mkForce "0440";
    }) apps;

  # Quadlet unit の置き場所。
  #
  # 当初は deploy ユーザのホーム (~/.config/containers/systemd) に置いたが、
  # systemd-tmpfiles が中間ディレクトリを root 所有で作ってしまい、
  #   Detected unsafe path transition /var/lib/deploy-template (owned by
  #   deploy-template) → /var/lib/deploy-template/.config (owned by root)
  # として以降のルールを拒否する。結果 podman も
  #   path ".../.config" exists and it is not owned by the current user
  # で起動できなかった。
  #
  # Quadlet は rootless でも /etc/containers/systemd/users/<uid>/ を探すので、
  # そちらへ置く。root 所有のまま environment.etc で宣言でき、ホーム配下の
  # 所有権を一切触らずに済む。
  environment.etc = lib.listToAttrs (lib.flatten (lib.mapAttrsToList (name: app:
    map (color: {
      name = "containers/systemd/users/${toString app.uid}/${name}-${color}.container";
      value = { source = mkContainerFile name app color; };
    }) colors
  ) apps));

  systemd.services = lib.mapAttrs' (name: app:
    lib.nameValuePair "${name}-secrets" (mkSecretLinkService name app)) apps;

  environment.systemPackages = lib.mapAttrsToList mkDeployScript apps;

  # opkssh の認可。アプリ repo の main への push だけを、その deploy ユーザとして
  # 受け付ける。
  services.opkssh.authorizations = lib.mapAttrsToList (name: app: {
    user = deployUser name;
    principal = "repo:${app.repo}:ref:refs/heads/main";
    issuer = "https://token.actions.githubusercontent.com";
  }) apps;

  # HAProxy。ヘルスチェックだけで振り分けを追従させる。
  services.haproxy = {
    enable = true;
    config = ''
      global
        log /dev/log local0
        maxconn 2048

      defaults
        mode http
        log global
        option httplog
        timeout connect 5s
        timeout client  60s
        timeout server  60s

      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: app: ''
        frontend ${name}
          bind 127.0.0.1:${toString app.frontendPort}
          default_backend ${name}

        backend ${name}
          option httpchk GET ${app.healthPath}
          http-check expect status 200
      '' + lib.concatMapStringsSep "\n" (color:
        "    server ${color} 127.0.0.1:${toString app.colorPorts.${color}} check inter 3s fall 2 rise 3"
      ) colors) apps)}
    '';
  };
}
