# IronClaw AI agent runtime configuration
# Runs IronClaw via Podman with PostgreSQL + Ollama backend
# Secrets managed by agenix

{ config, pkgs, lib, ... }:

let
  ironclawEnvScript = pkgs.writeShellScript "ironclaw-env" ''
    POSTGRES_PASSWORD=$(cat ${config.age.secrets.ironclaw-db-password.path})
    mkdir -p /var/lib/ironclaw
    cat > /var/lib/ironclaw/env << EOF
DATABASE_URL=postgres://ironclaw:$POSTGRES_PASSWORD@host.containers.internal:5432/ironclaw
LLM_BACKEND=ollama
LLM_BASE_URL=http://host.containers.internal:11434
LLM_MODEL=qwen3.5:4b
EOF
    chmod 600 /var/lib/ironclaw/env
  '';
in
{
  # IronClaw data directory
  systemd.tmpfiles.rules = lib.mkAfter [
    "d /var/lib/ironclaw 0700 root root -"
    "d /var/lib/ironclaw/data 0700 1000 1000 -"
  ];

  # Generate environment file before container starts
  systemd.services.ironclaw-env = {
    description = "Generate IronClaw environment configuration";
    wantedBy = [ "podman-ironclaw.service" ];
    before = [ "podman-ironclaw.service" ];
    after = [ "postgresql.service" "ollama.service" ];
    requires = [ "postgresql.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = ironclawEnvScript;
    };
  };

  # Set PostgreSQL password for ironclaw user
  systemd.services.ironclaw-db-setup = {
    description = "Setup IronClaw database user password";
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];
    wantedBy = [ "podman-ironclaw.service" ];
    before = [ "podman-ironclaw.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "postgres";
      ExecStart = pkgs.writeShellScript "setup-ironclaw-db" ''
        POSTGRES_PASSWORD=$(cat ${config.age.secrets.ironclaw-db-password.path})
        ${config.services.postgresql.package}/bin/psql -c "ALTER USER ironclaw WITH PASSWORD '$POSTGRES_PASSWORD';"
      '';
    };
  };

  # IronClaw container service using Podman
  virtualisation.oci-containers.containers.ironclaw = {
    image = "ghcr.io/nearai/ironclaw:latest";
    autoStart = true;
    ports = [ "127.0.0.1:3000:3000" ];
    volumes = [ "/var/lib/ironclaw/data:/home/ironclaw/.ironclaw" ];
    environment = {
      RUST_LOG = "ironclaw=info";
      TZ = "Asia/Tokyo";
    };
    environmentFiles = [ "/var/lib/ironclaw/env" ];
    extraOptions = [
      "--user=1000:1000"
      "--add-host=host.containers.internal:host-gateway"
    ];
  };

  # Ensure ironclaw container starts after all dependencies
  systemd.services.podman-ironclaw = {
    after = [
      "postgresql.service"
      "ollama.service"
      "ironclaw-env.service"
      "ironclaw-db-setup.service"
      "postgresql-pgvector-init.service"
    ];
    requires = [
      "postgresql.service"
      "ollama.service"
      "ironclaw-env.service"
      "ironclaw-db-setup.service"
    ];
  };
}
