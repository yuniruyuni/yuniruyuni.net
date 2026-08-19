# サービスごとの microVM。
#
# 狙いは、デプロイ用の SSH 接続先をホストからサービス側の VM へ移すこと。
# 証明書が漏れても届く範囲がその VM に閉じ、ホストの Postgres や他サービスへ
# 横断できない。ホスト自身の sshd (ssh.yuniruyuni.net) は従来のまま残す。
#
# ネットワークは qemu の user mode を使い、ホスト側に bridge も NAT も
# 作らない。VPS のネットワークを壊すとトンネル経由の唯一のアクセス手段を
# 失うため、ホストの設定に手を入れない方式を選んでいる。
# VM 間通信が必要になった時点で bridge 方式へ移す。

{ config, lib, pkgs, ... }:

let
  # ホスト側で cloudflared が転送する先。
  hostSSHPort = 2222;

  # CA 公開鍵だけを置くディレクトリ。
  #
  # /var/lib/oidc-ssh-ca には秘密鍵も入っているため、そのまま共有すると
  # VM から CA 秘密鍵が読めてしまう。公開鍵だけを別ディレクトリへ複製して
  # 読み取り専用で渡す。
  caShareDir = "/var/lib/oidc-ssh-ca-pub";
in
{
  # CA 公開鍵を共有用ディレクトリへ複製する。
  systemd.services.oidc-ssh-ca-pubkey = {
    description = "Publish the oidc-ssh-ca public key for microVM shares";
    wantedBy = [ "multi-user.target" ];
    after = [ "oidc-ssh-ca-keygen.service" ];
    requires = [ "oidc-ssh-ca-keygen.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      install -d -m 0755 ${caShareDir}
      install -m 0444 /var/lib/oidc-ssh-ca/ca.pub ${caShareDir}/ca.pub
    '';
  };

  microvm.vms.demo = {
    config = {
      microvm = {
        hypervisor = "qemu";
        mem = 512;
        vcpu = 1;

        # ホスト側の設定を要さない user mode networking。
        interfaces = [{
          type = "user";
          id = "vm-demo";
          mac = "02:00:00:00:00:01";
        }];

        # ホストの 2222 を VM の sshd へ転送する。
        # ホストの firewall は allowedTCPPorts = [] なので外部からは届かず、
        # cloudflared だけが localhost 経由で到達する。
        forwardPorts = [{
          from = "host";
          host.port = hostSSHPort;
          guest.port = 22;
        }];

        shares = [
          {
            source = "/nix/store";
            mountPoint = "/nix/.ro-store";
            tag = "ro-store";
            proto = "virtiofs";
          }
          # CA 公開鍵のみ。秘密鍵は渡さない。
          {
            source = caShareDir;
            mountPoint = "/run/ca";
            tag = "ca";
            proto = "virtiofs";
          }
        ];
      };

      system.stateVersion = "25.11";

      networking = {
        hostName = "demo";
        firewall.enable = false; # user mode networking の内側なので不要
      };

      services.openssh = {
        enable = true;
        settings = {
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
          PermitRootLogin = "no";
          # ホスト側と同様、既定値が先に書き出されるため settings で指定する。
          AuthorizedPrincipalsFile = "/etc/ssh/principals/%u";
        };
        extraConfig = ''
          TrustedUserCAKeys /run/ca/ca.pub
        '';
      };

      # 許可する principal。証明書の principal がここに無ければ通らない。
      environment.etc."ssh/principals/deploy" = {
        text = "demo\n";
        mode = "0444";
      };

      users.users.deploy = {
        isSystemUser = true;
        group = "deploy";
        home = "/var/lib/deploy";
        createHome = true;
        shell = pkgs.bashInteractive;
      };
      users.groups.deploy = { };

      # force-command から実行されるスクリプト。呼び出し側は動詞しか選べない。
      environment.systemPackages = [
        (pkgs.writeShellScriptBin "app-deploy" ''
          set -euo pipefail
          cmd="''${SSH_ORIGINAL_COMMAND:-}"
          set -- $cmd
          case "''${1:-}" in
            status)
              echo "microVM 内で force-command が強制されている"
              echo "host=$(hostname) user=$(id -un)"
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
        '')
      ];
    };
  };
}
