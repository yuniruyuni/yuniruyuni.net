{
  description = "NixOS configuration for Contabo VPS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    # Secret management
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, agenix, ... }: {
    nixosConfigurations.vps = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        # Hardware configuration (generated on VPS)
        ./hardware-configuration.nix

        # Main configuration
        ./configuration.nix

        # Agenix module for secrets
        agenix.nixosModules.default
        ({ pkgs, ... }: {
          # Agenix configuration
          # Use converted age key (generated from SSH host key via ssh-to-age)
          age.identityPaths = [ "/var/lib/agenix/age-key.txt" ];

          # Ensure age key exists (convert from SSH host key)
          system.activationScripts.agenixKey = {
            text = ''
              if [ ! -f /var/lib/agenix/age-key.txt ]; then
                mkdir -p /var/lib/agenix
                ${pkgs.ssh-to-age}/bin/ssh-to-age -private-key < /etc/ssh/ssh_host_ed25519_key > /var/lib/agenix/age-key.txt
                chmod 600 /var/lib/agenix/age-key.txt
              fi
            '';
            deps = [ ];
          };

          # agenixInstall はこの鍵で復号するので、必ず agenixKey の後に走らせる。
          #
          # 既定では順序制約が無く、実際に activate 上では agenixInstall が
          # 59 行目、agenixKey が 538 行目という逆順に並んでいた。鍵が既に
          # 存在する平常時は表面化しないが、VPS をフル再構築したときに
          # 初回 activation で全 secret の復号に失敗し、2 回目でようやく
          # 通るという挙動になる。DR 経路で踏むので順序を固定する。
          #
          # なお /etc/ssh/ssh_host_ed25519_key 自体は sshd の起動時に作られる
          # ため、本当に何も無い状態からでは初回 activation では鍵を作れない。
          # そもそも新しく生成したホスト鍵では既存の secret を復号できない
          # (secrets.nix の vps 受信者と一致しない) ので、フル再構築時は
          # ホスト鍵を復元するか 1Password の鍵で rekey する必要がある。
          # この順序修正が効くのは「ホスト鍵を復元した後の初回 switch」である。
          system.activationScripts.agenixInstall.deps = [ "agenixKey" ];
        })

        # Secrets configuration
        ./secrets.nix
      ];
    };

    # For deploy-rs or manual deployment
    # Usage: nixos-rebuild switch --flake .#vps --target-host yuniruyuni@ssh.yuniruyuni.net
  };
}
