# oidc-ssh-ca — GitHub Actions の OIDC トークンから短命 SSH 証明書を発行する。
#
# これにより、デプロイ用の長期 SSH 秘密鍵を GitHub secrets へ置く必要が
# なくなる。証明書には force-command を焼くため、資格情報が漏れても
# 「決められたスクリプトを実行する」以上のことはできない。
#
# 現状は検証目的の導入。CA 鍵はサービスが初回起動時に生成する
# (generateCAKey)。運用に移す際は agenix 管理の鍵を caKeyFile で渡し、
# 再構築で失われないようにすること。

{ config, lib, pkgs, oidc-ssh-ca, ... }:

let
  # デプロイ用のログインユーザ。各アプリの証明書はこのユーザへログインし、
  # 実際に何ができるかは証明書に焼かれた force-command で決まる。
  deployUser = "deploy";

  # 検証用のデプロイスクリプト。呼び出し側は digest しか渡せない。
  #
  # podman や systemctl を GitHub Actions 側に書かせないための層でもある。
  # ここに一度だけ書けば、全アプリで同じ手順になる。
  deployScript = pkgs.writeShellScript "app-deploy" ''
    set -euo pipefail

    # SSH_ORIGINAL_COMMAND 以外からは何も受け取らない。
    cmd="''${SSH_ORIGINAL_COMMAND:-}"
    set -- $cmd
    verb="''${1:-}"

    case "$verb" in
      status)
        echo "oidc-ssh-ca 経由の接続に成功した"
        echo "user=$(id -un) principal 経由で force-command が強制されている"
        ;;
      echo)
        shift || true
        echo "received: $*"
        ;;
      *)
        echo "使える動詞: status | echo <text>" >&2
        exit 64
        ;;
    esac
  '';
in
{
  users.users.${deployUser} = {
    isSystemUser = true;
    group = deployUser;
    home = "/var/lib/${deployUser}";
    createHome = true;
    shell = pkgs.bashInteractive;
  };
  users.groups.${deployUser} = { };

  # このユーザに許可する principal。証明書の principal がここに無ければ
  # 認証は通らない。
  environment.etc."ssh/principals/${deployUser}".text = ''
    demo
  '';

  services.openssh.extraConfig = ''
    # oidc-ssh-ca が発行した証明書を信頼する。
    TrustedUserCAKeys ${config.services.oidc-ssh-ca.caPublicKeyPath}
    AuthorizedPrincipalsFile /etc/ssh/principals/%u
  '';

  services.oidc-ssh-ca = {
    enable = true;
    package = oidc-ssh-ca;
    listen = "127.0.0.1:8129";

    # 検証用。運用へ移す際は agenix の鍵を caKeyFile で渡す。
    generateCAKey = true;

    rules = [{
      name = "demo";
      audience = "https://ssh-ca.yuniruyuni.net";

      # 数値 ID で縛る。リポジトリのリネームと、解放された名前の
      # 再取得による成りすましを防ぐため。
      repository_id = "1339035542";
      repository_owner_id = "85034901";
      workflow_ref = "yuniruyuni/oidc-ssh-ca/.github/workflows/vps-demo.yml@refs/heads/main";
      job_workflow_ref = "yuniruyuni/oidc-ssh-ca/.github/workflows/vps-demo.yml@refs/heads/main";
      ref = "refs/heads/main";

      principals = [ "demo" ];
      force_command = "${deployScript}";
      validity = "5m";
    }];
  };
}
