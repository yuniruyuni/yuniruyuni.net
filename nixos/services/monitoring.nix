# Monitoring services configuration
# - mackerel-agent: External monitoring service
# Secrets managed by agenix

{ config, pkgs, lib, ... }:

let
  # Script to generate mackerel-agent config from agenix secret
  mackerelConfigScript = pkgs.writeShellScript "mackerel-config" ''
    APIKEY=$(cat ${config.age.secrets.mackerel-api-key.path})
    mkdir -p /var/lib/mackerel-agent
    cat > /var/lib/mackerel-agent/mackerel-agent.conf << EOF
    apikey = "$APIKEY"
    pidfile = "/run/mackerel-agent/mackerel-agent.pid"
    root = "/var/lib/mackerel-agent"
    EOF
    chown -R mackerel-agent:mackerel-agent /var/lib/mackerel-agent
    chmod 600 /var/lib/mackerel-agent/mackerel-agent.conf
  '';
in
{
  # mackerel-agent - External monitoring
  environment.systemPackages = [ pkgs.mackerel-agent ];

  # Config generation runs as root before the service starts
  systemd.services.mackerel-agent-config = {
    description = "Generate Mackerel Agent Configuration";
    wantedBy = [ "mackerel-agent.service" ];
    before = [ "mackerel-agent.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = mackerelConfigScript;
      RemainAfterExit = true;
    };
  };

  systemd.services.mackerel-agent = {
    description = "Mackerel Agent";
    after = [ "network-online.target" "mackerel-agent-config.service" ];
    wants = [ "network-online.target" ];
    requires = [ "mackerel-agent-config.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.mackerel-agent}/bin/mackerel-agent -conf=/var/lib/mackerel-agent/mackerel-agent.conf";
      Restart = "on-failure";
      RestartSec = "10s";
      User = "mackerel-agent";
      Group = "mackerel-agent";
      RuntimeDirectory = "mackerel-agent";
      RuntimeDirectoryMode = "0755";
    };
  };

  # Create mackerel-agent user
  users.users.mackerel-agent = {
    isSystemUser = true;
    group = "mackerel-agent";
    home = "/var/lib/mackerel-agent";
    createHome = true;
  };

  users.groups.mackerel-agent = { };
}
