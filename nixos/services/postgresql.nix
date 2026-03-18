# PostgreSQL service configuration
# Provides database backend for IronClaw with pgvector extension

{ config, pkgs, lib, ... }:

{
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16;
    enableTCPIP = true;

    authentication = lib.mkOverride 10 ''
      local   all             all                                     peer
      host    all             all             127.0.0.1/32            scram-sha-256
      host    all             all             ::1/128                 scram-sha-256
    '';

    ensureDatabases = [ "ironclaw" ];
    ensureUsers = [
      { name = "ironclaw"; ensureDBOwnership = true; }
    ];

    settings = {
      shared_preload_libraries = "vector";
      max_connections = 100;
      shared_buffers = "256MB";
    };
  };

  environment.systemPackages = [ pkgs.postgresql16Packages.pgvector ];

  # Initialize pgvector extension after database creation
  systemd.services.postgresql-pgvector-init = {
    description = "Initialize pgvector extension for IronClaw";
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "postgres";
      ExecStart = pkgs.writeShellScript "init-pgvector" ''
        ${pkgs.postgresql_16}/bin/psql -d ironclaw -c "CREATE EXTENSION IF NOT EXISTS vector;"
      '';
    };
  };
}
