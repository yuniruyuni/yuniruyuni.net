# Backup/restore configuration for VPS services
# Uses rclone to backup to Google Drive
#
# Scripts provided:
# - incus-personal-create: Create fresh personal Arch Linux container
# - incus-personal-backup: Backup personal container to Google Drive
# - incus-personal-restore: Restore personal container from Google Drive
# - n8n-backup: Backup n8n data to Google Drive
# - n8n-restore: Restore n8n data from Google Drive
#
# Automated daily backup via systemd timer

{ config, pkgs, lib, ... }:

let
  # Backup destination on Google Drive
  gdrive_remote = "gdrive";
  gdrive_path_incus = "incus";
  gdrive_path_n8n = "n8n";

  # Backup staging directory (restricted permissions, avoids world-readable /tmp)
  staging_dir = "/var/lib/backups/staging";

  # Container configuration
  container_name = "personal";
  container_ip = "10.155.247.20";
  container_cpu = "2";
  container_memory = "2GB";

  # Age public key for backup encryption (1Password infrastructure-admin)
  # Decrypt with: age -d -i <infrastructure-admin-age-key> <file>.age
  age_recipient = "age1t5u8r467lwp2t5d0qjr38va4nmly3wyg5k9fwttaakmu66q4zyvqq58qav";

  # rclone config path (generated from agenix secret)
  rclone_config_path = "/var/lib/rclone/rclone.conf";

  # Script to generate rclone config from agenix secret
  rcloneConfigScript = pkgs.writeShellScript "rclone-config-setup" ''
    mkdir -p /var/lib/rclone
    chown root:incus-admin /var/lib/rclone
    chmod 770 /var/lib/rclone
    cp ${config.age.secrets.rclone-config.path} ${rclone_config_path}
    chown root:incus-admin ${rclone_config_path}
    chmod 660 ${rclone_config_path}
  '';

  # Create fresh personal container script
  incusPersonalCreate = pkgs.writeShellScriptBin "incus-personal-create" ''
    set -euo pipefail

    echo "Creating fresh personal Arch Linux container..."

    # Check if container already exists
    if incus list --format csv -c n | grep -q "^${container_name}$"; then
      echo "Error: Container '${container_name}' already exists."
      echo "Delete it first with: incus delete ${container_name} --force"
      exit 1
    fi

    # Launch container
    incus launch images:archlinux ${container_name} \
      --config limits.cpu=${container_cpu} \
      --config limits.memory=${container_memory}

    echo "Waiting for container to start..."
    sleep 5

    # Configure static IP via netplan-like approach for Arch
    # Arch uses systemd-networkd
    incus exec ${container_name} -- bash -c 'cat > /etc/systemd/network/10-static.network << EOF
[Match]
Name=eth0

[Network]
Address=${container_ip}/24
Gateway=10.155.247.1
DNS=10.155.247.1
EOF'

    incus exec ${container_name} -- systemctl enable systemd-networkd
    incus exec ${container_name} -- systemctl restart systemd-networkd

    echo "Container '${container_name}' created successfully!"
    echo "IP: ${container_ip}"
    incus list ${container_name}
  '';

  # Backup container to Google Drive
  incusPersonalBackup = pkgs.writeShellScriptBin "incus-personal-backup" ''
    set -euo pipefail

    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_PREFIX="${staging_dir}/${container_name}-backup-$TIMESTAMP"
    BACKUP_FILE="$BACKUP_PREFIX.tar.gz"  # incus adds .tar.gz automatically
    RCLONE_CONFIG="${rclone_config_path}"

    echo "Starting backup of '${container_name}' container..."

    # Check if container exists
    if ! incus list --format csv -c n | grep -q "^${container_name}$"; then
      echo "Error: Container '${container_name}' does not exist."
      exit 1
    fi

    # Export container as image (includes all data)
    # --force stops and restarts the container during export
    echo "Exporting container to image..."
    incus publish ${container_name} --alias ${container_name}-backup-temp --force

    echo "Exporting image to file..."
    incus image export ${container_name}-backup-temp "$BACKUP_PREFIX"

    # Cleanup temporary image
    incus image delete ${container_name}-backup-temp

    # Encrypt backup before upload
    echo "Encrypting backup..."
    ENCRYPTED_FILE="$BACKUP_FILE.age"
    ${pkgs.age}/bin/age -r "${age_recipient}" -o "$ENCRYPTED_FILE" "$BACKUP_FILE"
    rm -f "$BACKUP_FILE"

    echo "Uploading to Google Drive..."
    ${pkgs.rclone}/bin/rclone --config "$RCLONE_CONFIG" \
      copy "$ENCRYPTED_FILE" ${gdrive_remote}:${gdrive_path_incus}/ \
      --progress

    # Keep only last 7 backups on Google Drive
    echo "Cleaning up old backups..."
    ${pkgs.rclone}/bin/rclone --config "$RCLONE_CONFIG" \
      delete ${gdrive_remote}:${gdrive_path_incus}/ \
      --min-age 7d

    # Cleanup local temp file
    rm -f "$ENCRYPTED_FILE"

    echo "Backup completed successfully!"
    echo "Uploaded: ${gdrive_remote}:${gdrive_path_incus}/$(basename $ENCRYPTED_FILE)"
  '';

  # Restore container from Google Drive
  incusPersonalRestore = pkgs.writeShellScriptBin "incus-personal-restore" ''
    set -euo pipefail

    RCLONE_CONFIG="${rclone_config_path}"
    RESTORE_DIR="${staging_dir}/incus-restore"

    echo "Listing available backups..."
    ${pkgs.rclone}/bin/rclone --config "$RCLONE_CONFIG" \
      ls ${gdrive_remote}:${gdrive_path_incus}/ | grep "${container_name}-backup" | sort -r | head -10

    echo ""
    read -p "Enter backup filename to restore (or 'latest' for most recent): " BACKUP_NAME

    if [ "$BACKUP_NAME" = "latest" ]; then
      BACKUP_NAME=$(${pkgs.rclone}/bin/rclone --config "$RCLONE_CONFIG" \
        ls ${gdrive_remote}:${gdrive_path_incus}/ | grep "${container_name}-backup" | sort -r | head -1 | awk '{print $2}')
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

    # Check if container already exists
    if incus list --format csv -c n | grep -q "^${container_name}$"; then
      echo "Warning: Container '${container_name}' already exists!"
      read -p "Delete existing container and restore? (yes/no): " CONFIRM
      if [ "$CONFIRM" != "yes" ]; then
        echo "Restore cancelled."
        exit 0
      fi
      echo "Stopping and deleting existing container..."
      incus stop ${container_name} --force 2>/dev/null || true
      incus delete ${container_name} --force
    fi

    # Download backup
    mkdir -p "$RESTORE_DIR"
    echo "Downloading backup from Google Drive..."
    ${pkgs.rclone}/bin/rclone --config "$RCLONE_CONFIG" \
      copy ${gdrive_remote}:${gdrive_path_incus}/"$BACKUP_NAME" "$RESTORE_DIR/" \
      --progress

    # Decrypt backup
    echo "Decrypting backup..."
    DECRYPTED_FILE="$RESTORE_DIR/$(basename "$BACKUP_NAME" .age)"
    ${pkgs.age}/bin/age -d -i "$AGE_KEY" -o "$DECRYPTED_FILE" "$RESTORE_DIR/$BACKUP_NAME"
    rm -f "$RESTORE_DIR/$BACKUP_NAME"

    # Import image
    echo "Importing container image..."
    incus image import "$DECRYPTED_FILE" --alias ${container_name}-restored

    # Launch container from image
    echo "Launching container from backup..."
    incus launch ${container_name}-restored ${container_name}

    # Cleanup
    incus image delete ${container_name}-restored
    rm -rf "$RESTORE_DIR"

    echo "Restore completed successfully!"
    incus list ${container_name}
  '';

  # n8n data directory
  n8n_data_dir = "/var/lib/n8n/data";

  # Backup n8n to Google Drive
  n8nBackup = pkgs.writeShellScriptBin "n8n-backup" ''
    set -euo pipefail

    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_FILE="${staging_dir}/n8n-backup-$TIMESTAMP.tar.gz"
    RCLONE_CONFIG="${rclone_config_path}"

    echo "Starting backup of n8n data..."

    # Stop n8n for consistent backup
    echo "Stopping n8n..."
    sudo systemctl stop podman-n8n || true
    sleep 2

    # Create backup
    echo "Creating archive..."
    sudo tar -czf "$BACKUP_FILE" -C "$(dirname ${n8n_data_dir})" "$(basename ${n8n_data_dir})"
    sudo chown $(id -u):$(id -g) "$BACKUP_FILE"

    # Restart n8n
    echo "Restarting n8n..."
    sudo systemctl start podman-n8n

    # Encrypt backup before upload
    echo "Encrypting backup..."
    ENCRYPTED_FILE="$BACKUP_FILE.age"
    ${pkgs.age}/bin/age -r "${age_recipient}" -o "$ENCRYPTED_FILE" "$BACKUP_FILE"
    rm -f "$BACKUP_FILE"

    echo "Uploading to Google Drive..."
    ${pkgs.rclone}/bin/rclone --config "$RCLONE_CONFIG" \
      copy "$ENCRYPTED_FILE" ${gdrive_remote}:${gdrive_path_n8n}/ \
      --progress

    # Keep only last 7 backups on Google Drive
    echo "Cleaning up old backups..."
    ${pkgs.rclone}/bin/rclone --config "$RCLONE_CONFIG" \
      delete ${gdrive_remote}:${gdrive_path_n8n}/ \
      --min-age 7d

    # Cleanup local temp file
    rm -f "$ENCRYPTED_FILE"

    echo "Backup completed successfully!"
    echo "Uploaded: ${gdrive_remote}:${gdrive_path_n8n}/$(basename $ENCRYPTED_FILE)"
  '';

  # Restore n8n from Google Drive
  n8nRestore = pkgs.writeShellScriptBin "n8n-restore" ''
    set -euo pipefail

    RCLONE_CONFIG="${rclone_config_path}"
    RESTORE_DIR="${staging_dir}/n8n-restore"

    echo "Listing available backups..."
    ${pkgs.rclone}/bin/rclone --config "$RCLONE_CONFIG" \
      ls ${gdrive_remote}:${gdrive_path_n8n}/ | grep "n8n-backup" | sort -r | head -10

    echo ""
    read -p "Enter backup filename to restore (or 'latest' for most recent): " BACKUP_NAME

    if [ "$BACKUP_NAME" = "latest" ]; then
      BACKUP_NAME=$(${pkgs.rclone}/bin/rclone --config "$RCLONE_CONFIG" \
        ls ${gdrive_remote}:${gdrive_path_n8n}/ | grep "n8n-backup" | sort -r | head -1 | awk '{print $2}')
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
      copy ${gdrive_remote}:${gdrive_path_n8n}/"$BACKUP_NAME" "$RESTORE_DIR/" \
      --progress

    # Decrypt backup
    echo "Decrypting backup..."
    DECRYPTED_FILE="$RESTORE_DIR/$(basename "$BACKUP_NAME" .age)"
    ${pkgs.age}/bin/age -d -i "$AGE_KEY" -o "$DECRYPTED_FILE" "$RESTORE_DIR/$BACKUP_NAME"
    rm -f "$RESTORE_DIR/$BACKUP_NAME"

    # Stop n8n
    echo "Stopping n8n..."
    sudo systemctl stop podman-n8n || true
    sleep 2

    # Backup current data (just in case)
    if [ -d "${n8n_data_dir}" ]; then
      echo "Backing up current data..."
      sudo mv "${n8n_data_dir}" "${n8n_data_dir}.bak.$(date +%Y%m%d_%H%M%S)"
    fi

    # Restore data
    echo "Restoring data..."
    sudo mkdir -p "$(dirname ${n8n_data_dir})"
    sudo tar -xzf "$DECRYPTED_FILE" -C "$(dirname ${n8n_data_dir})"
    sudo chown -R 1000:1000 "${n8n_data_dir}"

    # Restart n8n
    echo "Restarting n8n..."
    sudo systemctl start podman-n8n

    # Cleanup
    rm -rf "$RESTORE_DIR"

    echo "Restore completed successfully!"
  '';

in
{
  # Backup staging directory with restricted permissions
  systemd.tmpfiles.rules = [
    "d /var/lib/backups/staging 0700 yuniruyuni users -"
  ];

  # Install rclone and helper scripts
  environment.systemPackages = [
    pkgs.rclone
    pkgs.age
    incusPersonalCreate
    incusPersonalBackup
    incusPersonalRestore
    n8nBackup
    n8nRestore
  ];

  # rclone config setup service (runs before backup)
  systemd.services.rclone-config-setup = {
    description = "Setup rclone configuration from agenix secret";
    wantedBy = [ "multi-user.target" ];
    before = [ "incus-personal-backup.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = rcloneConfigScript;
      RemainAfterExit = true;
    };
  };

  # Daily backup timer
  systemd.timers.incus-personal-backup = {
    description = "Daily backup of personal Incus container";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };

  # Backup service
  systemd.services.incus-personal-backup = {
    description = "Backup personal Incus container to Google Drive";
    after = [ "network-online.target" "rclone-config-setup.service" "incus.service" ];
    wants = [ "network-online.target" ];
    requires = [ "rclone-config-setup.service" ];
    path = [ pkgs.incus pkgs.rclone pkgs.age pkgs.coreutils pkgs.gnugrep ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${incusPersonalBackup}/bin/incus-personal-backup";
      TimeoutStartSec = "30min";
    };
  };

  # Daily n8n backup timer
  systemd.timers.n8n-backup = {
    description = "Daily backup of n8n data";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };

  # n8n backup service
  systemd.services.n8n-backup = {
    description = "Backup n8n data to Google Drive";
    after = [ "network-online.target" "rclone-config-setup.service" ];
    wants = [ "network-online.target" ];
    requires = [ "rclone-config-setup.service" ];
    path = [ pkgs.rclone pkgs.age pkgs.coreutils pkgs.gnugrep pkgs.gnutar pkgs.gzip ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${n8nBackup}/bin/n8n-backup";
      TimeoutStartSec = "30min";
    };
  };
}
