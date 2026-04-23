# PostgreSQL 18 service configuration
# Provides database services for Cloud Run applications via Cloudflare Tunnel
#
# Design: Each app gets its own database + 2 users:
#   - ${app.name}      : DB owner, used for migration (DDL)
#   - ${app.name}_app  : application user (DML only)
# Access: localhost only (tunnel handles external connectivity)
# New app: add entry to dbApps list + create 2 agenix secrets
#
# pgschemaManagesGrants:
#   true  = per-table GRANT / ALTER DEFAULT PRIVILEGES はアプリ側 (pgschema
#           declarative) が管理する。NixOS は CONNECT / schema USAGE のみ付与
#           (推奨: 新 table を追加する際に GRANT が migration で同時反映され、
#           permission denied の時間帯が発生しない)
#   false = NixOS 側で GRANT ... ON ALL TABLES + ALTER DEFAULT PRIVILEGES を
#           activation 毎に一括付与する (pgschema 移行前のアプリ向け fallback)
# 詳細は StreamTagInventory の ADR 0009 を参照。

{ config, pkgs, lib, ... }:

let
  dbApps = [
    { name = "stream_tag_inventory"; pgschemaManagesGrants = true; }
    { name = "template";             pgschemaManagesGrants = false; }
  ];
in
{
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_18;

    settings = {
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
      { name = app.name; ensureDBOwnership = true; } # owner/migration (DDL)
      { name = "${app.name}_app"; }                   # application (DML only)
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
      name = "db-password-${app.name}_app";
      value = {
        file = ../secrets/db-password-${app.name}_app.age;
        owner = "postgres";
        mode = "0400";
      };
    }
  ]) dbApps);

  # Set passwords + DB/schema-level privileges after PostgreSQL starts.
  # app.pgschemaManagesGrants = true のアプリは per-table GRANT / ALTER DEFAULT
  # PRIVILEGES を pgschema 側で宣言するため、ここでは発行しない。false のアプリは
  # 従来通り NixOS 側で GRANT ... ON ALL TABLES 等を付与する fallback パスを通る。
  systemd.services.postgresql-app-credentials = {
    after = [ "postgresql.service" "postgresql-setup.service" ];
    requires = [ "postgresql.service" "postgresql-setup.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
      ExecStart = pkgs.writeShellScript "postgresql-app-credentials" (
        lib.concatMapStringsSep "\n" (app: let
          psql = "${config.services.postgresql.package}/bin/psql";
          db = app.name;
          owner = app.name;
          appUser = "${app.name}_app";
          # per-table / ALTER DEFAULT PRIVILEGES を pgschema 管理に委ねるか
          pgschemaManaged = app.pgschemaManagesGrants or false;
          legacyTableGrants = lib.optionalString (!pgschemaManaged) ''
            GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO ${appUser};
            GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO ${appUser};
            ALTER DEFAULT PRIVILEGES FOR ROLE ${owner} IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ${appUser};
            ALTER DEFAULT PRIVILEGES FOR ROLE ${owner} IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO ${appUser};
          '';
        in ''
          OWNER_PW=$(cat ${config.age.secrets."db-password-${app.name}".path})
          APP_PW=$(cat ${config.age.secrets."db-password-${app.name}_app".path})
          ${psql} -d ${db} <<SQL
            ALTER USER ${owner} WITH PASSWORD '$OWNER_PW';
            ALTER USER ${appUser} WITH PASSWORD '$APP_PW';
            GRANT CONNECT ON DATABASE ${db} TO ${appUser};
            GRANT USAGE ON SCHEMA public TO ${appUser};
            ${legacyTableGrants}
          SQL
        '') dbApps
      );
    };
  };
}
