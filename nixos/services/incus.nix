# Incus service configuration
# Provides LXC containers for personal Arch Linux environment

{ config, pkgs, ... }:

{
  # Enable Incus
  virtualisation.incus = {
    enable = true;
    # LTS 系列 (7.0.x) に固定する。
    #
    # NixOS 25.11 の pkgs.incus は 7.0.0 で、26.05 では feature release の
    # 7.5.x に進む。Incus はアップグレード時に自身の DB スキーマを一方向に
    # 移行するので、OS の更新と同時に 7.5 へ上げると、問題が出て前の世代へ
    # 戻したときに 7.0 の incusd が新しいスキーマを読めず起動しなくなる。
    #
    # 26.05 の pkgs.incus-lts は 7.0.1 で、稼働中の 7.0.0 と同じ系列。
    # OS の更新ではパッチ更新に留め、ロールバックの経路を残す。
    # feature release に戻すときは別の変更として行うこと (戻せない移行になる)。
    package = pkgs.incus-lts;
    ui.enable = true;  # Optional: Web UI
  };

  # Add user to incus-admin group (handled in main config)
  # users.users.yuniruyuni.extraGroups = [ "incus-admin" ];

  # Network bridge for containers
  networking.bridges.incusbr0 = {
    interfaces = [ ];
  };

  networking.interfaces.incusbr0 = {
    ipv4.addresses = [{
      address = "10.155.247.1";
      prefixLength = 24;
    }];
  };

  # NAT for container internet access
  networking.nat = {
    enable = true;
    internalInterfaces = [ "incusbr0" ];
    externalInterface = "eth0";  # Adjust if different
  };

  # DNS/DHCP for containers (dnsmasq)
  services.dnsmasq = {
    enable = true;
    settings = {
      interface = "incusbr0";
      bind-interfaces = true;
      dhcp-range = [ "10.155.247.100,10.155.247.200,1h" ];
      dhcp-option = [
        "option:router,10.155.247.1"
        "option:dns-server,10.155.247.1"
      ];
    };
  };

  # Firewall rules for Incus bridge
  networking.firewall.trustedInterfaces = [ "incusbr0" ];
}

# Note: After deployment, create the personal container:
#
# incus launch images:archlinux personal \
#   --config limits.cpu=2 \
#   --config limits.memory=2GB
#
# Configure static IP:
# incus config device override personal eth0 ipv4.address=10.155.247.20
#
# SSH proxy (optional):
# incus config device add personal ssh-proxy proxy \
#   listen=tcp:127.0.0.1:2222 connect=tcp:10.155.247.20:22
