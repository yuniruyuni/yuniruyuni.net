# NixOS VPS Configuration
# Contabo VPS with:
# - Podman (rootless) for n8n
# - Incus for personal Arch Linux container
# - cloudflared for tunnel access

{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./services/cloudflared.nix
    ./services/n8n.nix
    ./services/incus.nix
    ./services/incus-backup.nix
    ./services/monitoring.nix
    ./services/ollama.nix
  ];

  # Boot configuration
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";  # Contabo typically uses /dev/sda

  # Networking
  networking = {
    hostName = "vps";
    useDHCP = true;

    # Required for Incus
    nftables.enable = true;

    firewall = {
      enable = true;
      # No ports open to internet - all access via Cloudflare Tunnel
      allowedTCPPorts = [ ];
      trustedInterfaces = [ "incusbr0" "incusbr1" ];  # Allow Incus container traffic
    };
  };

  # Timezone
  time.timeZone = "Asia/Tokyo";

  # Locale
  i18n.defaultLocale = "en_US.UTF-8";

  # User configuration
  users.users.yuniruyuni = {
    isNormalUser = true;
    description = "yuniruyuni";
    extraGroups = [ "wheel" "podman" "incus-admin" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINNgQ6u084ZWWEpXB/ikcbWOn3xRPNjzPMwOzHsYj458 yuniruyuni@MacBook-Air"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC6/vedtV7hyu88uHVfwZpm4w2KPYgZqZkmBTKBcnwvP github-actions@infrastructure"
    ];
  };

  # Enable sudo without password for wheel group
  security.sudo.wheelNeedsPassword = false;

  # SSH brute-force protection
  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "1h";
  };

  # SSH configuration
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      X11Forwarding = false;
    };
  };

  # System packages
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    tmux
    curl
    wget
    jq
    docker-compose
  ];

  # Enable Podman (rootless Docker alternative)
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;  # Provides 'docker' command alias
    defaultNetwork.settings.dns_enabled = true;
  };

  # Podman socket for docker-compose compatibility
  virtualisation.containers.enable = true;

  # Sysctl security settings
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;
  };

  # Enable automatic garbage collection
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # Enable flakes (optional, for future use)
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # System version
  system.stateVersion = "24.05";
}
