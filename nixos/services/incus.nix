# Incus service configuration
# Provides LXC containers for personal Arch Linux environment

{ config, pkgs, ... }:

{
  # Enable Incus
  virtualisation.incus = {
    enable = true;
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
