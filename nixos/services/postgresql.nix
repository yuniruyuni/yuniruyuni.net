# PostgreSQL 18 service configuration
# Provides database services for Cloud Run applications via Cloudflare Tunnel
#
# Design: Each app gets its own database + 2 users (admin for DDL, app for DML)
# Access: localhost only (tunnel handles external connectivity)
# New app: add entry to dbApps list + create 2 agenix secrets

{ config, pkgs, lib, ... }:

let
  dbApps = [
    { name = "stream_tag_inventory"; }
    # New apps: add here
  ];
in
{
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_18;

    settings = {
      listen_addresses = "127.0.0.1";
      port = 5432;
      # Prevent ALTER USER passwords from appearing in PG logs
      log_statement = "none";
    };

    # Authentication: md5 for local TCP connections
    authentication = ''
      # TYPE  DATABASE        USER            ADDRESS         METHOD
      local   all             postgres                        peer
      host    all             all             127.0.0.1/32    md5
    '';

    # Create application databases and users (derived from dbApps)
    ensureDatabases = map (app: app.name) dbApps;
    ensureUsers = lib.concatMap (app: [
      { name = "${app.name}_admin"; ensureDBOwnership = true; } # migration (DDL)
      { name = app.name; }                                      # application (DML only)
    ]) dbApps;
  };

  # Password secrets (derived from dbApps: 2 per app)
  age.secrets = lib.listToAttrs (lib.concatMap (app: [
    {
      name = "db-password-${app.name}";
      value = {
        file = ../secrets/db-password-${app.name}.age;
        owner = "postgres";
        mode = "0400";
      };
    }
    {
      name = "db-password-${app.name}_admin";
      value = {
        file = ../secrets/db-password-${app.name}_admin.age;
        owner = "postgres";
        mode = "0400";
      };
    }
  ]) dbApps);

  # Set passwords + grant DML privileges after PostgreSQL starts
  systemd.services.postgresql-setup = {
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
      ExecStart = pkgs.writeShellScript "postgresql-setup" (
        lib.concatMapStringsSep "\n" (app: let
          psql = "${config.services.postgresql.package}/bin/psql";
          db = app.name;
          admin = "${app.name}_admin";
          appUser = app.name;
        in ''
          ADMIN_PW=$(cat ${config.age.secrets."db-password-${app.name}_admin".path})
          APP_PW=$(cat ${config.age.secrets."db-password-${app.name}".path})
          ${psql} -d ${db} <<SQL
            ALTER USER ${admin} WITH PASSWORD '$ADMIN_PW';
            ALTER USER ${appUser} WITH PASSWORD '$APP_PW';
            GRANT CONNECT ON DATABASE ${db} TO ${appUser};
            GRANT USAGE ON SCHEMA public TO ${appUser};
            GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO ${appUser};
            GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO ${appUser};
            ALTER DEFAULT PRIVILEGES FOR ROLE ${admin} IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ${appUser};
            ALTER DEFAULT PRIVILEGES FOR ROLE ${admin} IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO ${appUser};
          SQL
        '') dbApps
      );
    };
  };
}
