# PostgreSQL 18 service configuration
# Provides database services for Cloud Run applications via Cloudflare Tunnel
#
# Design: Each app gets its own database + 2 users:
#   - <name>       : DB owner, used for migration (DDL)
#   - <name>_app   : application user (DML only)
# Access: localhost only (tunnel handles external connectivity)
# New app: add name to dbApps list + create 2 agenix secrets
#
# 権限の責務分担:
#   NixOS (ここ)  : ロールの存在、パスワード、DB の所有権、
#                   app ロールへの CONNECT と schema USAGE
#   pgschema (app): table 等のオブジェクトと、app ロールへの per-table GRANT
#
# table 単位の権限は必ずアプリ側の schema ファイルで宣言する。pgschema は
# 宣言的なので、宣言されていない権限は「余分なもの」として REVOKE される。
# NixOS 側から GRANT ... ON ALL TABLES を撒くと、それが毎回 REVOKE されては
# activation で復活する振動になり、その間 app ロールが permission denied になる。
# 実際 template でこれが起きていた (2026-08-21 に解消)。
#
# 「宣言し忘れた table は権限が付かない」= deploy 時に気づける、という性質を
# 保つのが狙い。詳細は StreamTagInventory の ADR 0009 を参照。

{ config, pkgs, lib, ... }:

let
  dbApps = [
    "stream_tag_inventory"
    "template"
    "fighter"
    "streamer_post"
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
    #
    # local の md5 行は VPS 上のコンテナ向け。コンテナは独立した netns に
    # 置いており、ホストの 127.0.0.1:5432 には到達できない。そこで
    # /run/postgresql の Unix ソケットを bind mount して繋ぐ (services/apps.nix)。
    # 既定では postgres 以外は peer 認証になり "Peer authentication failed" で
    # 弾かれるため、パスワード認証を許可する行を足す。
    #
    # 到達性は TCP の 127.0.0.1/32 md5 と同じ (ローカルからパスワードで接続) で、
    # 権限が増えるわけではない。
    authentication = ''
      # TYPE  DATABASE        USER            ADDRESS         METHOD
      local   all             postgres                        peer
      local   all             all                             md5
      host    all             all             127.0.0.1/32    md5
    '';

    # Create application databases and users (derived from dbApps)
    ensureDatabases = dbApps;
    ensureUsers = lib.concatMap (app: [
      # schema apply (DDL) を行う owner。apply する権限の出所は GRANT ではなく
      # DB の所有権そのもの。所有者は自分が作ったオブジェクトを所有するので
      # 明示的な GRANT は要らず、pgschema が権限を宣言的に管理しても自分自身を
      # 締め出すことがない。
      { name = app; ensureDBOwnership = true; }
      # アプリ用 (DML のみ)。所有権は持たせない。
      # nixpkgs 側に「同名の database が ensureDatabases に無いと true にできない」
      # という assertion があるため、_app ロールは構造的に所有者になれない。
      { name = "${app}_app"; ensureDBOwnership = false; }
    ]) dbApps;
  };

  # Password secrets (derived from dbApps: 2 per app)
  age.secrets = lib.listToAttrs (lib.concatMap (app: [
    {
      name = "db-password-${app}";
      value = {
        file = ../secrets/db-password-${app}.age;
        owner = "postgres";
        mode = "0400";
      };
    }
    {
      name = "db-password-${app}_app";
      value = {
        file = ../secrets/db-password-${app}_app.age;
        owner = "postgres";
        mode = "0400";
      };
    }
  ]) dbApps);

  # Set passwords + DB/schema-level privileges after PostgreSQL starts.
  #
  # ここで発行するのは「どの table があるかに依存しない」ものだけに限る。
  # per-table GRANT と ALTER DEFAULT PRIVILEGES は発行しない。撒くと pgschema に
  # 毎回 REVOKE され、次の activation で復活する振動になるため。
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
          appUser = "${app}_app";
        in ''
          OWNER_PW=$(cat ${config.age.secrets."db-password-${app}".path})
          APP_PW=$(cat ${config.age.secrets."db-password-${app}_app".path})
          ${psql} -d ${app} <<SQL
            ALTER USER ${app} WITH PASSWORD '$OWNER_PW';
            ALTER USER ${appUser} WITH PASSWORD '$APP_PW';
            GRANT CONNECT ON DATABASE ${app} TO ${appUser};
            GRANT USAGE ON SCHEMA public TO ${appUser};
          SQL
        '') dbApps
      );
    };
  };
}
