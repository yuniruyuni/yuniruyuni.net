# n8n service configuration
# Runs n8n via Podman (rootless Docker alternative)
# Secrets managed by agenix

{ config, pkgs, lib, ... }:

{
  # n8n data directory
  systemd.tmpfiles.rules = lib.mkAfter [
    "d /var/lib/n8n 0700 yuniruyuni users -"
    "d /var/lib/n8n/data 0700 yuniruyuni users -"
  ];

  # n8n container service using Podman
  virtualisation.oci-containers = {
    backend = "podman";
    containers = {
      n8n = {
        image = "n8nio/n8n:2.11.4";
        autoStart = true;
        ports = [ "127.0.0.1:5678:5678" ];
        volumes = [
          "/var/lib/n8n/data:/home/node/.n8n"
        ];
        environment = {
          GENERIC_TIMEZONE = "Asia/Tokyo";
          TZ = "Asia/Tokyo";
          WEBHOOK_URL = "https://n8n.yuniruyuni.net";
        };
        # Use agenix-managed secret
        environmentFiles = [
          config.age.secrets.n8n-encryption-key.path
        ];
        extraOptions = [
          "--user=1000:1000"  # Run as non-root
        ];
      };
    };
  };

}
