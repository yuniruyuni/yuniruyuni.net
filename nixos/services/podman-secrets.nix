# podman secret を agenix に接続する
#
# 狙いは「インフラ側 (この repo) で DB や資格情報を定義したら、それがそのまま
# 該当サービスの podman secret として参照できる」という契約を作ること。
# アプリ側の Quadlet は
#
#   Secret=streamer-post-better-auth-secret,type=env,target=BETTER_AUTH_SECRET
#
# と書くだけでよく、秘密の受け渡し方法を各アプリが知る必要がなくなる。
#
# ■ なぜ既定の file ドライバを使わないか
#
# podman の既定 (file ドライバ) は秘密を base64 で
# ~/.local/share/containers/storage/secrets/filedriver/secretsdata.json に
# 永続保存する。実測で復元可能なことを確認済み。base64 は暗号化ではないので、
# これはディスク上の平文と同義であり、agenix を tmpfs に展開している意味を
# 失わせる。
#
# ■ shell ドライバの契約
#
# podman は秘密の取得を外部コマンドへ委譲できる。コマンドには環境変数
# SECRET_ID が渡され、値は stdin/stdout でやり取りする。値を podman 側に
# 保存させないので、ディスクには何も残らない。
#
# ただし SECRET_ID に渡るのは podman が生成した不透明な ID であって、
# 人が付けた名前ではない (実測で確認)。そのため ID から agenix の secret 名を
# 引くための対応表が要る。
#
# 対応表に入るのは「agenix secret の名前」だけで秘密そのものではないため、
# 永続化しても情報は漏れない。podman secret create の stdin にも、秘密ではなく
# 参照先の名前を渡す。
#
# ■ 権限について
#
# lookup は podman を動かしているユーザ自身として実行される。つまりこの仕組みで
# 読めるのは、そのユーザが元々 /run/agenix 上で読めるファイルだけであり、
# 新たな権限は生まれない。どの secret を誰に読ませるかは secrets.nix の
# owner/group で決まる。

{ pkgs, lib, ... }:

# NOTE: 各スクリプトは podman から呼ばれる。podman が渡す PATH は最小限で
# coreutils すら入っていないため、先頭で明示的に PATH を通す必要がある。
# これを怠ると lookup が
#   podman-secret-lookup: line 3: cat: command not found
# で失敗し、コンテナ起動が "no such secret" になる。

let
  # 対応表の置き場所。秘密ではなく名前しか入らない。
  mapDir = "$HOME/.local/state/podman-secret-names";

  # agenix secret 名として許す文字。`..` や `/` を弾いて、対応表の内容で
  # /run/agenix の外へ出られないようにする (lookup は呼び出しユーザ権限で
  # 動くので昇格はしないが、意図しないファイルを読ませない)。
  validateName = ''
    case "$name" in
      "" | *[!A-Za-z0-9._-]* | *..* )
        echo "podman-secret: invalid agenix secret name: $name" >&2
        exit 1
        ;;
    esac
  '';

  lookupScript = pkgs.writeShellScript "podman-secret-lookup" ''
    set -eu
    export PATH=${lib.makeBinPath [ pkgs.coreutils ]}
    name=$(cat "${mapDir}/$SECRET_ID")
    ${validateName}
    exec cat "/run/agenix/$name"
  '';

  # 作成時の stdin には秘密ではなく「参照先 agenix secret の名前」が来る。
  storeScript = pkgs.writeShellScript "podman-secret-store" ''
    set -eu
    export PATH=${lib.makeBinPath [ pkgs.coreutils ]}
    mkdir -p "${mapDir}"
    name=$(cat)
    ${validateName}
    printf '%s' "$name" > "${mapDir}/$SECRET_ID"
  '';

  deleteScript = pkgs.writeShellScript "podman-secret-delete" ''
    set -eu
    export PATH=${lib.makeBinPath [ pkgs.coreutils ]}
    rm -f "${mapDir}/$SECRET_ID"
  '';

  listScript = pkgs.writeShellScript "podman-secret-list" ''
    set -eu
    export PATH=${lib.makeBinPath [ pkgs.coreutils ]}
    ls "${mapDir}" 2>/dev/null || true
  '';
in
{
  virtualisation.containers.containersConf.settings = {
    secrets = {
      driver = "shell";
      opts = {
        lookup = "${lookupScript}";
        store = "${storeScript}";
        delete = "${deleteScript}";
        list = "${listScript}";
      };
    };
  };

  # agenix secret を podman secret として登録するためのヘルパ。
  #
  # 冪等にするため、既に同名があれば作り直す。渡すのは名前だけなので、
  # このコマンドライン自体に秘密は乗らない (ps に出ても問題ない)。
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "podman-secret-link" ''
      set -eu
      if [ $# -ne 1 ] && [ $# -ne 2 ]; then
        echo "usage: podman-secret-link <agenix-secret-name> [podman-secret-name]" >&2
        exit 1
      fi
      agenix_name="$1"
      podman_name="''${2:-$1}"

      if [ ! -r "/run/agenix/$agenix_name" ]; then
        echo "podman-secret-link: /run/agenix/$agenix_name is not readable by $(id -un)" >&2
        exit 1
      fi

      ${pkgs.podman}/bin/podman secret rm "$podman_name" >/dev/null 2>&1 || true
      printf '%s' "$agenix_name" | ${pkgs.podman}/bin/podman secret create "$podman_name" - >/dev/null
      echo "linked podman secret '$podman_name' -> /run/agenix/$agenix_name"
    '')
  ];
}
