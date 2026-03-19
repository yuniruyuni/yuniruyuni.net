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
        })

        # Secrets configuration
        ./secrets.nix
      ];
    };

    # For deploy-rs or manual deployment
    # Usage: nixos-rebuild switch --flake .#vps --target-host yuniruyuni@ssh.yuniruyuni.net
  };
}
