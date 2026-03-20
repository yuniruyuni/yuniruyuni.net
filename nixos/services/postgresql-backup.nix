# PostgreSQL backup configuration
# Daily pg_dumpall backup, encrypted with age, uploaded to Google Drive via rclone
# Follows the same pattern as incus-backup.nix

{ config, pkgs, ... }:

let
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
    RCLONE_CONFIG="${rclone_config_path}"

    echo "Starting PostgreSQL backup..."

    # Hot backup using pg_dumpall (no downtime)
    echo "Dumping all databases..."
    sudo -u postgres ${pkgs.postgresql_18}/bin/pg_dumpall | ${pkgs.gzip}/bin/gzip > "$BACKUP_FILE"

    # Encrypt backup before upload
    echo "Encrypting backup..."
    ENCRYPTED_FILE="$BACKUP_FILE.age"
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
      --min-age 7d

    # Cleanup local temp file
    rm -f "$ENCRYPTED_FILE"

    echo "Backup completed successfully!"
    echo "Uploaded: ${gdrive_remote}:${gdrive_path}/$(basename $ENCRYPTED_FILE)"
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

    # Restore
    echo "Restoring databases..."
    ${pkgs.gzip}/bin/gunzip -c "$DECRYPTED_FILE" | sudo -u postgres ${pkgs.postgresql_18}/bin/psql

    # Cleanup
    rm -rf "$RESTORE_DIR"

    echo "Restore completed successfully!"
  '';

in
{
  # Install helper scripts
  environment.systemPackages = [
    postgresqlBackup
    postgresqlRestore
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
    path = [ pkgs.postgresql_18 pkgs.rclone pkgs.age pkgs.coreutils pkgs.gzip pkgs.sudo ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${postgresqlBackup}/bin/postgresql-backup";
      TimeoutStartSec = "30min";
    };
  };
}
