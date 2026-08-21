# NixOS VPS Configuration
# Contabo VPS with:
# - Podman (rootless) for n8n
# - Incus for personal Arch Linux container
# - cloudflared for tunnel access

{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./services/apps.nix
    ./services/cloudflared.nix
    ./services/n8n.nix
    ./services/incus.nix
    ./services/incus-backup.nix
    ./services/monitoring.nix
    ./services/opkssh.nix
    ./services/podman-secrets.nix
    ./services/postgresql.nix
    ./services/postgresql-backup.nix
    ./services/swap.nix
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
    # 個人端末からの手動操作・フル再セットアップ用。
    #
    # GitHub Actions からのデプロイはここではなく opkssh (services/opkssh.nix) が
    # 発行する短命証明書で行う。ここに残っている鍵は、opkssh や sshd を壊す変更を
    # 入れてしまったときの復旧経路でもあるため、両方を同時に失わないよう
    # 個人鍵は必ず残す。
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINNgQ6u084ZWWEpXB/ikcbWOn3xRPNjzPMwOzHsYj458 yuniruyuni@MacBook-Air"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICzxszhOK9EyGC/PJr7Wn/BjDHU02b2F1j8etTbSak4l yuniruyuni@WSL"
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
