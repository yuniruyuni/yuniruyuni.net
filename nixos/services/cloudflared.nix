# cloudflared service configuration
# Provides secure tunnel access to the VPS
# Secrets managed by agenix

{ config, pkgs, lib, ... }:

{
  # Install cloudflared
  environment.systemPackages = [ pkgs.cloudflared ];

  # cloudflared systemd service
  systemd.services.cloudflared = {
    description = "Cloudflare Tunnel";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "notify";
      TimeoutStartSec = 0;
      ExecStart = "${pkgs.cloudflared}/bin/cloudflared --no-autoupdate tunnel run";
      Restart = "on-failure";
      RestartSec = "5s";

      # Security hardening
      User = "cloudflared";
      Group = "cloudflared";
      # Use agenix-managed secret
      EnvironmentFile = config.age.secrets.cloudflared-token.path;
    };
  };

  # Create cloudflared user
  users.users.cloudflared = {
    isSystemUser = true;
    group = "cloudflared";
    home = "/var/lib/cloudflared";
    createHome = true;
  };

  users.groups.cloudflared = { };
}
