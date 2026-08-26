# アプリごとの PostgreSQL のバックアップ
#
# 1 日 1 回、DB を持つアプリを順に pg_dump し、まとめて 1 つのアーカイブに
# して age で暗号化し Google Drive へ上げる。7 世代保持。
#
# 2026-08-23 まで共有インスタンス 1 台を pg_dumpall で丸ごと取っていた。DB を
# アプリごとのコンテナに分けたので、対象を宣言から引く形にした。
#
# 対象は yunirun databases から引く。DB 名やソケットの場所をここで推測すると、
# 規約を変えたときに静かにずれる。ずれても「取れた分だけ成功」に見えるのが
# 厄介で、気付くのは復元しようとした時になる。
#
# 採取は root がホストの pg_dump でソケット越しに行う。podman を経由する必要は
# ない。ソケットは bind mount でホスト側に見えている。
#
# yunirun は絶対パスで呼ぶ。systemd の unit は環境変数を引き継がないので、
# PATH に入っている前提で書くと command not found で落ちる。

{ config, pkgs, ... }:

let

  # バックアップが成功した事実を計測基盤へ残す道具。ExecStartPost から呼ぶ。
  backupMetric = import ../pkgs/backup-metric.nix { inherit pkgs; };
  # 置き場は yunirun の計測基盤が作る。中身が何かは yunirun 側は知らない。
  textfileDir = "${config.services.yunirun.observability.dir}/textfile";
  # Backup destination on Google Drive
  gdrive_remote = "gdrive";
  gdrive_path = "postgresql";

  # Backup staging directory
  staging_dir = "/var/lib/backups/staging";

  # Age public key for backup encryption (1Password infrastructure-admin)
  age_recipient = "age1t5u8r467lwp2t5d0qjr38va4nmly3wyg5k9fwttaakmu66q4zyvqq58qav";

  # rclone config path
  rclone_config_path = "/var/lib/rclone/rclone.conf";

  # Backup script
  postgresqlBackup = pkgs.writeShellScriptBin "postgresql-backup" ''
    set -euo pipefail

    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_FILE="${staging_dir}/postgresql-backup-$TIMESTAMP.sql.gz"
    ENCRYPTED_FILE="$BACKUP_FILE.age"
    RCLONE_CONFIG="${rclone_config_path}"

    # Remove staging files on every exit path. With `set -e` a mid-script
    # failure used to skip the cleanup below and leave the *plaintext* dump
    # on disk indefinitely.
    cleanup() {
      rm -f "$BACKUP_FILE" "$ENCRYPTED_FILE"
    }
    trap cleanup EXIT

    echo "Starting PostgreSQL backup..."

    # 稼働したまま取れる。
    DUMPDIR=$(mktemp -d)
    trap 'rm -rf "$DUMPDIR"; cleanup' EXIT

    ${config.services.yunirun.package}/bin/yunirun databases \
      | ${pkgs.jq}/bin/jq -r '.[] | [.app, .name, .owner, .socketDir, .ownerPasswordFile] | @tsv' \
      > "$DUMPDIR/.targets"

    COUNT=0
    while IFS=$'\t' read -r APP DBNAME OWNER SOCK PWFILE; do
      [ -n "$APP" ] || continue
      echo "Dumping $APP ($DBNAME)..."
      PW=$(${pkgs.gnugrep}/bin/grep -oP '(?<=DB_PASSWORD=).*' "$PWFILE")
      PGPASSWORD="$PW" ${pkgs.postgresql_18}/bin/pg_dump \
        -h "$SOCK" -U "$OWNER" -d "$DBNAME" -Fc -f "$DUMPDIR/$APP.dump"
      COUNT=$((COUNT + 1))
    done < "$DUMPDIR/.targets"
    rm -f "$DUMPDIR/.targets"

    # 1 つも取れないのは異常。黙って空のアーカイブを上げない。
    if [ "$COUNT" -eq 0 ]; then
      echo "ERROR: 取得できた DB が 1 つも無い"
      exit 1
    fi
    echo "Dumped $COUNT databases."
    ${pkgs.gnutar}/bin/tar -czf "$BACKUP_FILE" -C "$DUMPDIR" .

    # Encrypt backup before upload
    echo "Encrypting backup..."
    ${pkgs.age}/bin/age -r "${age_recipient}" -o "$ENCRYPTED_FILE" "$BACKUP_FILE"
    rm -f "$BACKUP_FILE"

    echo "Uploading to Google Drive..."
    ${pkgs.rclone}/bin/rclone --config "$RCLONE_CONFIG" \
      copy "$ENCRYPTED_FILE" ${gdrive_remote}:${gdrive_path}/ \
      --progress

    # Keep only last 7 backups on Google Drive
    echo "Cleaning up old backups..."
    ${pkgs.rclone}/bin/rclone --config "$RCLONE_CONFIG" \
      delete ${gdrive_remote}:${gdrive_path}/ \
      --min-age 7d \
      --drive-use-trash=false

    echo "Backup completed successfully!"
    echo "Uploaded: ${gdrive_remote}:${gdrive_path}/$(basename $ENCRYPTED_FILE)"
  '';

  # 復元の演習。
  #
  # 取れていることと戻せることは別で、戻したことのないバックアップは
  # バックアップではなく仮説になる。dump の形式・所有者・GRANT のどれか 1 つが
  # 噛み合わないだけで、必要になった当日に初めて分かる。
  #
  # 作業用の DB へ戻すので稼働中のデータには触れない。作る DB も消す DB も
  # 名前が _drill で終わるものだけに限っている。
  #
  # 暗号文そのものは復号しない。鍵はホストに置いていない (ホストを失っても
  # 復旧できるようにするため) ので、ここで確かめられるのは「採ったものが
  # 戻せるか」と「置いたものが在るか」まで。鍵で開けることは人が確かめる。
  postgresqlRestoreDrill = pkgs.writeShellScriptBin "postgresql-restore-drill" ''
    set -uo pipefail

    RCLONE_CONFIG="${rclone_config_path}"
    D=$(mktemp -d)
    trap 'rm -rf "$D"' EXIT

    ${config.services.yunirun.package}/bin/yunirun databases \
      | ${pkgs.jq}/bin/jq -r '.[] | [.app,.name,.owner,.socketDir,.ownerPasswordFile] | @tsv' \
      > "$D/targets"

    FAIL=0
    COUNT=0
    while IFS=$'\t' read -r APP DB OWNER SOCK PWFILE; do
      [ -n "$APP" ] || continue
      PGPASSWORD=$(${pkgs.gnugrep}/bin/grep -oP '(?<=DB_PASSWORD=).*' "$PWFILE")
      export PGPASSWORD
      APPROLE="''${DB}_app"
      DRILL="''${DB}_drill"

      q() { ${pkgs.postgresql_18}/bin/psql -h "$SOCK" -U "$OWNER" -d "$1" -tAqc "$2" 2>/dev/null; }

      TABLES=$(q "$DB" "select count(*) from pg_stat_user_tables")
      ROWS=$(q "$DB" "select coalesce(sum(n_live_tup),0) from pg_stat_user_tables")

      if ! ${pkgs.postgresql_18}/bin/pg_dump -h "$SOCK" -U "$OWNER" -d "$DB" \
             -Fc -f "$D/$APP.dump" 2>"$D/e"; then
        echo "$APP: 採取に失敗"; ${pkgs.coreutils}/bin/head -3 "$D/e"; FAIL=1; continue
      fi

      ${pkgs.postgresql_18}/bin/dropdb -h "$SOCK" -U "$OWNER" --if-exists "$DRILL" 2>/dev/null
      ${pkgs.postgresql_18}/bin/createdb -h "$SOCK" -U "$OWNER" "$DRILL" 2>/dev/null
      ${pkgs.postgresql_18}/bin/pg_restore -h "$SOCK" -U "$OWNER" -d "$DRILL" "$D/$APP.dump" 2>"$D/e"
      # grep -c は 0 件でも終了コード 1 を返すので || で受ける。
      ERRS=$(${pkgs.gnugrep}/bin/grep -c "^pg_restore: error" "$D/e") || ERRS=0

      TABLES2=$(q "$DRILL" "select count(*) from pg_stat_user_tables")
      ROWS2=$(q "$DRILL" "select coalesce(sum(n_live_tup),0) from pg_stat_user_tables")
      # 表だけ出来て中身が空でも「戻せた」に見えるので行数まで見る。アプリの
      # ロールが読めるかも見る。ここが噛み合わないと、復元は成功したのに
      # アプリだけ動かない状態になる。
      BAD=$(q "$DRILL" "select count(*) from pg_class c
              join pg_stat_user_tables s on s.relid=c.oid
              where not has_table_privilege('$APPROLE', c.oid, 'SELECT')")

      echo "$APP ($DB): 表 $TABLES->$TABLES2 / 行 $ROWS->$ROWS2 / 読めない表 ''${BAD:-?} / error $ERRS"
      if [ "$TABLES" != "$TABLES2" ] || [ "$ROWS" != "$ROWS2" ] \
         || [ "''${BAD:-1}" != "0" ] || [ "$ERRS" != "0" ]; then
        echo "  NG"; ${pkgs.coreutils}/bin/head -4 "$D/e"; FAIL=1
      fi

      ${pkgs.postgresql_18}/bin/dropdb -h "$SOCK" -U "$OWNER" "$DRILL" 2>/dev/null
      COUNT=$((COUNT + 1))
    done < "$D/targets"

    if [ "$COUNT" -eq 0 ]; then
      echo "対象の DB が 1 つも無い"
      exit 1
    fi

    # 置いたものが在るかも見る。採って戻せても、上がっていなければ意味が無い。
    echo "保管先を確認..."
    NEWEST=$(${pkgs.rclone}/bin/rclone --config "$RCLONE_CONFIG" \
      lsjson ${gdrive_remote}:${gdrive_path}/ 2>/dev/null \
      | ${pkgs.jq}/bin/jq -r 'sort_by(.ModTime) | last | "\(.Name) \(.Size)"')
    if [ -z "$NEWEST" ] || [ "$NEWEST" = "null null" ]; then
      echo "  保管先に何も無い"; FAIL=1
    else
      echo "  最新: $NEWEST"
      SIZE=$(echo "$NEWEST" | ${pkgs.gawk}/bin/awk '{print $2}')
      # 空に近いものが上がっていたら、取れているように見えて中身が無い。
      if [ "''${SIZE:-0}" -lt 1024 ]; then
        echo "  中身が小さすぎる"; FAIL=1
      fi
    fi

    [ "$FAIL" = "0" ] || exit 1
    echo "$COUNT 個の DB を戻せることを確かめた。"
  '';

  # Restore script
  postgresqlRestore = pkgs.writeShellScriptBin "postgresql-restore" ''
    set -euo pipefail

    RCLONE_CONFIG="${rclone_config_path}"
    RESTORE_DIR="${staging_dir}/postgresql-restore"

    echo "Listing available backups..."
    ${pkgs.rclone}/bin/rclone --config "$RCLONE_CONFIG" \
      ls ${gdrive_remote}:${gdrive_path}/ | grep "postgresql-backup" | sort -r | head -10

    echo ""
    read -p "Enter backup filename to restore (or 'latest' for most recent): " BACKUP_NAME

    if [ "$BACKUP_NAME" = "latest" ]; then
      BACKUP_NAME=$(${pkgs.rclone}/bin/rclone --config "$RCLONE_CONFIG" \
        ls ${gdrive_remote}:${gdrive_path}/ | grep "postgresql-backup" | sort -r | head -1 | awk '{print $2}')
      echo "Using latest backup: $BACKUP_NAME"
    fi

    if [ -z "$BACKUP_NAME" ]; then
      echo "Error: No backup specified"
      exit 1
    fi

    echo ""
    read -p "Enter path to age identity file for decryption: " AGE_KEY

    if [ ! -f "$AGE_KEY" ]; then
      echo "Error: Identity file not found: $AGE_KEY"
      exit 1
    fi

    # Download backup
    mkdir -p "$RESTORE_DIR"
    echo "Downloading backup from Google Drive..."
    ${pkgs.rclone}/bin/rclone --config "$RCLONE_CONFIG" \
      copy ${gdrive_remote}:${gdrive_path}/"$BACKUP_NAME" "$RESTORE_DIR/" \
      --progress

    # Decrypt backup
    echo "Decrypting backup..."
    DECRYPTED_FILE="$RESTORE_DIR/$(basename "$BACKUP_NAME" .age)"
    ${pkgs.age}/bin/age -d -i "$AGE_KEY" -o "$DECRYPTED_FILE" "$RESTORE_DIR/$BACKUP_NAME"
    rm -f "$RESTORE_DIR/$BACKUP_NAME"

    # 展開だけして、流し込みは手で行う。
    #
    # アプリごとに別の DB なので、どれをどこへ戻すかは状況による。自動で全部
    # 戻すと、生きているアプリのデータまで巻き戻す。
    echo "Extracting..."
    ${pkgs.gnutar}/bin/tar -xzf "$DECRYPTED_FILE" -C "$RESTORE_DIR"
    rm -f "$DECRYPTED_FILE"

    echo ""
    echo "展開しました: $RESTORE_DIR"
    ls -la "$RESTORE_DIR"
    echo ""
    echo "戻すには、対象アプリを止めてから yunirun databases で接続先を確認し、"
    echo "pg_restore --clean --if-exists で流し込んでください。"
    echo "終わったら $RESTORE_DIR を消してください (平文が残ります)。"
  '';

in
{
  # Install helper scripts
  environment.systemPackages = [
    postgresqlBackup
    postgresqlRestore
    postgresqlRestoreDrill
  ];

  # Daily backup timer
  systemd.timers.postgresql-backup = {
    description = "Daily backup of PostgreSQL databases";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };

  # Backup service
  systemd.services.postgresql-backup = {
    description = "Backup PostgreSQL databases to Google Drive";
    after = [ "network-online.target" "rclone-config-setup.service" "postgresql.service" ];
    wants = [ "network-online.target" ];
    requires = [ "rclone-config-setup.service" ];
    path = [ pkgs.postgresql_18 pkgs.rclone pkgs.age pkgs.coreutils pkgs.gzip pkgs.gnutar pkgs.jq pkgs.gnugrep ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${postgresqlBackup}/bin/postgresql-backup";
      TimeoutStartSec = "30min";
      # ExecStart が 0 で終わったときにしか動かない。成功の判定を自前で書かずに済む。
      ExecStartPost = "${backupMetric}/bin/backup-metric ${textfileDir} postgresql";
    };
  };

  # 演習は毎日。1 度きりでは「あの日は戻せた」以上のことを言えない。
  #
  # バックアップと同じ頻度にしてあるので、指標も規則も既にあるものをそのまま
  # 使える (36 時間途絶えたら鳴る)。
  systemd.timers.postgresql-restore-drill = {
    description = "Daily restore drill";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };

  systemd.services.postgresql-restore-drill = {
    description = "Verify PostgreSQL backups can actually be restored";
    # 同時に走ると DB を取り合う。
    after = [ "postgresql-backup.service" ];
    path = [ pkgs.postgresql_18 pkgs.rclone pkgs.coreutils pkgs.jq pkgs.gnugrep pkgs.gawk ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${postgresqlRestoreDrill}/bin/postgresql-restore-drill";
      TimeoutStartSec = "30min";
      ExecStartPost = "${backupMetric}/bin/backup-metric ${textfileDir} restore-drill";
    };
  };
}
