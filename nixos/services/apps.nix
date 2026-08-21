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

        # スキーマ migration。持たないアプリは省略できる。
        #
        # owner ロール (DDL) を使う点がアプリ本体との違い。つまり deploy ユーザは
        # owner のパスワードも読めることになるが、これは「デプロイできる主体は
        # DDL を実行できる」という性質であって Cloud Run でも同じ (deploy SA が
        # migration job を実行できる)。
        migration = {
          image = "ghcr.io/yuniruyuni/template-migration";
          secret = "db-password-template";
          # migrate.sh が読む変数名はアプリごとに違うので明示する。
          # 接続ユーザは owner ロール (DDL) を使う。
          env = {
            DB_USER = "template";
            DB_NAME = "template";
          };
        };
      };
    };

    # DB を持たない静的寄りのアプリ。db を省略すると PostgreSQL 関連の設定と
    # migration 段がまるごと生成されない。
    costume = {
      uid = 985;
      repo = "yuniruyuni/costume";
      image = "ghcr.io/yuniruyuni/costume";
      frontendPort = 8120;
      colorPorts = { blue = 8121; green = 8122; };
      healthPath = "/health";
    };

    lom = {
      uid = 984;
      repo = "yuniruyuni/LegendOfManaWeapon";
      image = "ghcr.io/yuniruyuni/lom";
      # nginx で静的ファイルを配信するので 80 番。/health は無いので / を見る。
      containerPort = 80;
      frontendPort = 8130;
      colorPorts = { blue = 8131; green = 8132; };
      healthPath = "/";
    };

    web = {
      uid = 983;
      repo = "yuniruyuni/web";
      image = "ghcr.io/yuniruyuni/web";
      frontendPort = 8140;
      colorPorts = { blue = 8141; green = 8142; };
      healthPath = "/health";
    };

    stream_tag_inventory = {
      uid = 982;
      repo = "yuniruyuni/StreamTagInventory";
      image = "ghcr.io/yuniruyuni/stream-tag-inventory";
      frontendPort = 8150;
      colorPorts = { blue = 8151; green = 8152; };
      healthPath = "/health";

      env = {
        # OAuth の client_id は仕様上公開値。
        TWITCH_CLIENT_ID = "d2kz8x5se7k6b1n0picux0r7kaozi3";
        APP_BASE_URL = "https://tags.yuniruyuni.net";
      };

      db = {
        user = "stream_tag_inventory_app";
        name = "stream_tag_inventory";
        secret = "db-password-stream_tag_inventory_app";

        migration = {
          image = "ghcr.io/yuniruyuni/stream-tag-inventory-migration";
          secret = "db-password-stream_tag_inventory";
          env = {
            DB_USER = "stream_tag_inventory";
            DB_NAME = "stream_tag_inventory";
          };
        };
      };
    };

    streamer_post = {
      uid = 986;

      repo = "yuniruyuni/StreamerPost";
      image = "ghcr.io/yuniruyuni/streamer-post";

      frontendPort = 8110;
      colorPorts = {
        blue = 8111;
        green = 8112;
      };

      healthPath = "/health";

      # 非機密の環境変数。OAuth の client_id は仕様上公開値なのでここに置く。
      env = {
        APP_URL = "https://post.yuniruyuni.net";
        TWITCH_CLIENT_ID = "j9ix66xl3fho3phh67letqvghu5dy2";
        GOOGLE_CLIENT_ID = "249322615782-kpnt776l9k0li1fkmof069btpa8mvi9a.apps.googleusercontent.com";
      };

      # 秘密の環境変数。値は podman secret 経由で /run/agenix から実行時に取得され、
      # unit ファイルにもディスクにも現れない。
      envSecrets = {
        BETTER_AUTH_SECRET = "streamer-post-better-auth-secret";
        ALLOWED_EMAILS = "streamer-post-allowed-emails";
        TWITCH_CLIENT_SECRET = "streamer-post-twitch-client-secret";
        GOOGLE_CLIENT_SECRET = "streamer-post-google-client-secret";
      };

      db = {
        # StreamerPost は database 名を DB_APP_NAME で読む
        # (template の DB_NAME とは変数名が違う)。
        nameVar = "DB_APP_NAME";
        user = "streamer_post_app";
        name = "streamer_post";
        secret = "db-password-streamer_post_app";

        migration = {
          image = "ghcr.io/yuniruyuni/streamer-post-migration";
          secret = "db-password-streamer_post";
          # StreamerPost の migrate.sh は DB_APP_NAME を PGUSER と PGDATABASE の
          # 両方に使う。owner ロール名と database 名が同じなので成立する。
          env = {
            DB_APP_NAME = "streamer_post";
          };
        };
      };
    };
  };

  colors = [ "blue" "green" ];

  deployUser = name: "deploy-${name}";

  # deploy ユーザのグループ番号。uid の帯 (982-988) は他のシステムユーザと
  # 隣接していて衝突したので、空いている 5000 番台へ移す。
  deployGID = app: 5000 + (app.uid - 982);

  # 他所 (services/postgresql.nix) で定義済みの secret。ここでは group/mode を
  # 上書きするだけにする。
  sharedSecrets = app:
    lib.optionals (app ? db)
      ([ app.db.secret ] ++ lib.optional (app.db ? migration) app.db.migration.secret);

  # このアプリ専用の secret。定義ごとここで持つ。
  ownSecrets = app: lib.attrValues (app.envSecrets or { });

  # そのアプリの deploy ユーザが読む必要のある agenix secret すべて。
  appSecrets = app: sharedSecrets app ++ ownSecrets app;

  # コンテナが参照するローカルタグ。app-deploy が pull した image をこの名前に
  # 付け替えることで、unit 側は静的なまま中身だけ入れ替わる。
  localTag = name: "localhost/${name}:current";

  # コンテナ内で listen するポート。blue/green は netns 内では同じポートのままで、
  # ホスト側の公開ポートだけを分ける。
  containerPort = app: app.containerPort or 3000;

  mkContainerFile = name: app: color:
    pkgs.writeText "${name}-${color}.container" ''
      [Unit]
      Description=${name} (${color})

      [Container]
      Image=${localTag name}
      PublishPort=127.0.0.1:${toString app.colorPorts.${color}}:${toString (containerPort app)}
      Environment=PORT=${toString (containerPort app)}
${lib.optionalString (app ? db) ''
      # PostgreSQL へは Unix ソケットで繋ぐ。TCP を使わないので、この
      # コンテナからホストの loopback 上の他サービスへは到達できない。
      Volume=/run/postgresql:/run/postgresql
      Environment=PGHOST=/run/postgresql
      Environment=PGPORT=5432
      Environment=DB_USER=${app.db.user}
      Environment=${app.db.nameVar or "DB_NAME"}=${app.db.name}
      # 値は podman secret 経由で /run/agenix から実行時に取得される。
      # ディスクにも unit ファイルにも秘密は現れない (services/podman-secrets.nix)。
      Secret=${app.db.secret},type=env,target=DB_PASSWORD
''}
${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "      Environment=${k}=${v}") (app.env or { }))}
${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "      Secret=${v},type=env,target=${k}") (app.envSecrets or { }))}

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
    pkgs.writeShellScript "app-deploy-${name}" ''
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

      # ssh 経由の非対話セッションでは XDG_RUNTIME_DIR が設定されない。
      # 無いと systemctl --user が
      #   Failed to connect to user scope bus via local transport:
      #   $DBUS_SESSION_BUS_ADDRESS and $XDG_RUNTIME_DIR not defined
      # で失敗する。uid は表で固定してあるので補える。
      export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/${toString app.uid}}"
      runtime_dir="$XDG_RUNTIME_DIR"
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
${lib.optionalString ((app ? db) && (app.db ? migration)) ''
      # スキーマ migration を blue/green より前に一度だけ流す。
      #
      # set -e により、失敗した時点でここで止まり blue/green には触れない。
      # 逆に成功した場合は、旧コードが動いたままスキーマだけが進む区間ができる。
      # つまりスキーマ変更は新旧どちらのコードとも互換である必要がある
      # (expand/contract)。これは Cloud Run でも同じ制約。
      #
      # pgschema は宣言的で冪等なので、二重に流れても結果は変わらない。
      echo "==> pulling ${app.db.migration.image}:$tag"
      ${pkgs.podman}/bin/podman pull --authfile "$authfile" "${app.db.migration.image}:$tag"

      echo "==> applying schema migration"
      ${pkgs.coreutils}/bin/timeout 600 \
        ${pkgs.podman}/bin/podman run --rm \
          --secret ${app.db.migration.secret},type=env,target=DB_PASSWORD \
          --volume /run/postgresql:/run/postgresql \
          --env PGHOST=/run/postgresql \
          --env PGPORT=5432 \
${lib.concatStringsSep " \\\n" (lib.mapAttrsToList (k: v: "          --env ${k}=${v}") app.db.migration.env)} \
          "${app.db.migration.image}:$tag"
''}
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
  mkSecretLinkScript = name: app: pkgs.writeShellScript "link-${name}-secrets" (
    "set -eu\n" + lib.concatMapStringsSep "\n" (secret: ''
      ${pkgs.podman}/bin/podman secret rm ${secret} >/dev/null 2>&1 || true
      printf '%s' '${secret}' \
        | ${pkgs.podman}/bin/podman secret create ${secret} - >/dev/null
    '') (appSecrets app)
  );

  mkSecretLinkService = name: app: {
    description = "Link agenix secrets into podman for ${name}";
    wantedBy = [ "multi-user.target" ];
    # podman は secret 作成時の driver opts (lookup コマンドのパス等) を
    # メタデータに保存する。つまり containers.conf を書き換えても既存の secret は
    # 古いパスを参照し続ける。実際 lookup スクリプトを修正した際、
    # secret を作り直すまで古い store パスが呼ばれ続けた。
    # containers.conf が変わったら張り直す。
    restartTriggers = [ config.environment.etc."containers/containers.conf".source ];
    # rootless podman は /run/user/<uid> を要求する。linger を有効にしてあるので
    # user@<uid>.service が起動時に立ち上がり、そこで作られる。
    after = [ "user@${toString app.uid}.service" ];
    wants = [ "user@${toString app.uid}.service" ];
    # rootless podman は subuid/subgid を張るのに newuidmap/newgidmap を呼ぶ。
    # これは setuid が要るので /run/wrappers/bin に置かれているが、system
    # サービスの既定 PATH には含まれず
    #   command required for rootless mode with multiple IDs:
    #   exec: "newuidmap": executable file not found in $PATH
    # で落ちる。
    path = [ "/run/wrappers" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = deployUser name;
      Group = deployUser name;
      # 指定子 %U は使えない。system manager 上では User= を拾わず 0 に展開され、
      # podman が /run/user/0 を見に行って "Failed to obtain podman
      # configuration: lstat /run/user/0: no such file or directory" で落ちる。
      # uid は表で固定してあるのでそのまま埋める。
      Environment = [
        "HOME=/var/lib/${deployUser name}"
        "XDG_RUNTIME_DIR=/run/user/${toString app.uid}"
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

  # gid は uid とは別の帯から取る。
  #
  # gid = uid にしていたところ、他のユーザと番号が重なってグループが共有され、
  # deploy-web が template の DB パスワードを読める状態になっていた
  # (secret を 0440 root:deploy-template にしているため)。
  #
  # 番号を後から変えることもできない。NixOS は既存グループの gid 変更を
  # "not applying GID change" として拒否し、そのあと switch 自体が
  # "Failed to get GID for yuniruyuni" で失敗する (2026-08-22 に発生)。
  #
  # 5000 番台は空いているので、そこを deploy ユーザ専用にする。uid は据え置く。
  # 変えるとファイルの所有者がずれるため。
  users.groups = lib.mapAttrs' (name: app:
    lib.nameValuePair (deployUser name) { gid = deployGID app; }) apps;

  # DB パスワードは postgres (postgresql-app-credentials が User=postgres で読む) と
  # deploy ユーザの両方が読む必要があるので、group を広げる。
  # migration を持つアプリは owner 側のパスワードも対象になる。
  age.secrets = lib.listToAttrs (lib.flatten (lib.mapAttrsToList (name: app:
    # 他所で定義済みのものは group/mode だけ上書きする
    map (secret: {
      name = secret;
      value = {
        group = lib.mkForce (deployUser name);
        mode = lib.mkForce "0440";
      };
    }) (sharedSecrets app)
    # アプリ専用のものは定義ごと持つ
    ++ map (secret: {
      name = secret;
      value = {
        file = ../secrets/${secret}.age;
        owner = "root";
        group = deployUser name;
        mode = "0440";
      };
    }) (ownSecrets app)
  ) apps));

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

  # deploy ユーザが実行する入口。
  #
  # アプリごとに writeShellScriptBin "app-deploy" を作ると、どれも /bin/app-deploy
  # を提供するため environment.systemPackages 上で衝突し、PATH ではどれか 1 つだけが
  # 勝つ。実際 template のデプロイが StreamerPost の image を pull しようとして
  # 失敗した。
  #
  # 単一の app-deploy にして、呼び出しユーザで実体へ振り分ける。ssh 側のコマンドは
  # どのアプリでも "app-deploy <sha>" のままでよい。
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "app-deploy" ''
      set -euo pipefail
      case "$(${pkgs.coreutils}/bin/id -un)" in
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: app: ''
        ${deployUser name}) exec ${mkDeployScript name app} "$@" ;;'') apps)}
        *)
          echo "app-deploy: $(${pkgs.coreutils}/bin/id -un) に対応するアプリがありません" >&2
          exit 1
          ;;
      esac
    '')
  ];

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
          # Host ヘッダを明示的に送る。option httpchk の既定は HTTP/1.0 かつ
          # Host 無しで、Host によって振り分けるアプリはそれを 404 にする。
          # 実際 web がこれで DOWN のままだった (curl では 200 に見えるため
          # 原因が分かりにくい)。
          option httpchk
          http-check send meth GET uri ${app.healthPath} ver HTTP/1.1 hdr Host localhost
          http-check expect status 200
      '' + lib.concatMapStringsSep "\n" (color:
        "    server ${color} 127.0.0.1:${toString app.colorPorts.${color}} check inter 3s fall 2 rise 3"
      ) colors) apps)}
    '';
  };
}
