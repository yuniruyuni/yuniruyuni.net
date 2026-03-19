# NanoClaw AI agent runtime configuration
# Uses docker-compose (via podman-compose) for flexible configuration
# Discord Bot integration with container sandboxing
#
# Manual setup required after first deployment:
#   1. SSH to VPS: ssh yuniruyuni.net
#   2. Add Discord channel: sudo -u nanoclaw nanoclaw-add-discord
#   3. Check logs: journalctl -u podman-nanoclaw -f

{ config, pkgs, lib, ... }:

let
  # NanoClaw data directory
  nanoclawDir = "/var/lib/nanoclaw";

  # Docker-compose configuration for NanoClaw
  # Single container handles setup (npm ci, build) and runs the app
  # This avoids podman-compose depends_on race conditions
  # Using node:24 LTS (not slim) for native module compilation (better-sqlite3)
  dockerComposeContent = ''
    services:
      nanoclaw:
        image: node:24
        container_name: nanoclaw
        working_dir: /app
        command:
          - sh
          - -c
          - |
            echo "=== NanoClaw Startup ==="

            # Install dependencies if needed (check for .package-lock.json as completion marker)
            if [ ! -f node_modules/.package-lock.json ]; then
              echo "Installing dependencies (this may take a while for native modules)..."
              rm -rf node_modules
              npm ci --production=false
            fi

            # Build if needed
            if [ ! -f dist/index.js ]; then
              echo "Building NanoClaw..."
              npm run build
            fi

            echo "Starting NanoClaw..."
            exec node dist/index.js
        restart: unless-stopped
        env_file:
          - .env
        environment:
          - DOCKER_HOST=unix:///var/run/docker.sock
        volumes:
          # Mount source code (allows skill modifications)
          - ${nanoclawDir}/repo:/app:rw
          # Mount data directories
          - ${nanoclawDir}/data:/app/data:rw
          - ${nanoclawDir}/store:/app/store:rw
          - ${nanoclawDir}/groups:/app/groups:rw
          # Mount podman socket as docker socket
          - /run/podman/podman.sock:/var/run/docker.sock:rw
        networks:
          - nanoclaw-net

    networks:
      nanoclaw-net:
        driver: bridge
  '';

  # Environment file generation script
  nanoclawEnvScript = pkgs.writeShellScript "nanoclaw-env" ''
    DISCORD_TOKEN=$(cat ${config.age.secrets.discord-bot-token.path})

    cat > ${nanoclawDir}/.env << EOF
# Discord Bot
DISCORD_BOT_TOKEN=$DISCORD_TOKEN
ASSISTANT_NAME=MrDamian

# Ollama with Anthropic API compatibility
# Use host network IP for container access
ANTHROPIC_BASE_URL=http://host.containers.internal:11434/v1
ANTHROPIC_AUTH_TOKEN=ollama
MODEL=qwen3:4b

# Container settings
CONTAINER_RUNTIME=podman
CONTAINER_IMAGE=nanoclaw-agent:latest
MAX_CONCURRENT_CONTAINERS=2
CONTAINER_TIMEOUT=1800000
EOF
    chmod 600 ${nanoclawDir}/.env
    chown nanoclaw:nanoclaw ${nanoclawDir}/.env

    # Sync to container env directory
    mkdir -p ${nanoclawDir}/data/env
    cp ${nanoclawDir}/.env ${nanoclawDir}/data/env/env
    chown -R nanoclaw:nanoclaw ${nanoclawDir}/data
  '';

  # Git clone/update script
  nanoclawGitSetup = pkgs.writeShellScript "nanoclaw-git-setup" ''
    set -euo pipefail

    REPO_DIR="${nanoclawDir}/repo"

    if [ ! -d "$REPO_DIR/.git" ]; then
      echo "Cloning NanoClaw repository..."
      ${pkgs.git}/bin/git clone https://github.com/qwibitai/nanoclaw.git "$REPO_DIR"
    else
      echo "NanoClaw repository already exists"
      # Don't auto-update to preserve local skill modifications
    fi

    chown -R nanoclaw:nanoclaw "$REPO_DIR"
  '';

  # Build agent container image script
  nanoclawContainerBuild = pkgs.writeShellScript "nanoclaw-build-container" ''
    set -euo pipefail

    # Check if image already exists
    if ${pkgs.podman}/bin/podman image exists nanoclaw-agent:latest 2>/dev/null; then
      echo "Container image nanoclaw-agent:latest already exists, skipping build"
      exit 0
    fi

    echo "Building NanoClaw agent container image..."
    cd ${nanoclawDir}/repo/container
    ${pkgs.podman}/bin/podman build -t nanoclaw-agent:latest .
    echo "Container image built successfully"
  '';

  # Generate docker-compose.yml
  nanoclawComposeSetup = pkgs.writeShellScript "nanoclaw-compose-setup" ''
    cat > ${nanoclawDir}/docker-compose.yml << 'COMPOSE_EOF'
${dockerComposeContent}
COMPOSE_EOF
    chown nanoclaw:nanoclaw ${nanoclawDir}/docker-compose.yml
  '';

  # Helper script to add Discord channel (run after deployment)
  nanoclawAddDiscord = pkgs.writeShellScriptBin "nanoclaw-add-discord" ''
    echo "=== NanoClaw Discord Setup ==="
    echo ""
    echo "NanoClaw uses a skills-based architecture."
    echo "To add Discord support, you need to merge the Discord skill branch."
    echo ""
    echo "Steps:"
    echo "1. cd ${nanoclawDir}/repo"
    echo "2. git remote add upstream https://github.com/qwibitai/nanoclaw.git (if not added)"
    echo "3. git fetch upstream"
    echo "4. Look for Discord skill branch: git branch -r | grep -i discord"
    echo "5. Merge the skill: git merge upstream/skill/discord (or appropriate branch)"
    echo "6. Rebuild: npm run build"
    echo "7. Restart: sudo systemctl restart podman-nanoclaw"
    echo ""
    echo "Alternatively, check the NanoClaw documentation for /add-discord skill."
    echo ""
    echo "Current branches available:"
    cd ${nanoclawDir}/repo && ${pkgs.git}/bin/git branch -r 2>/dev/null | head -20 || echo "(repository not yet cloned)"
  '';

in
{
  # Create nanoclaw user and group
  users.users.nanoclaw = {
    isSystemUser = true;
    group = "nanoclaw";
    home = nanoclawDir;
    createHome = true;
    extraGroups = [ "podman" ];
  };
  users.groups.nanoclaw = {};

  # NanoClaw directories
  systemd.tmpfiles.rules = lib.mkAfter [
    "d ${nanoclawDir} 0750 nanoclaw nanoclaw -"
    "d ${nanoclawDir}/repo 0750 nanoclaw nanoclaw -"
    "d ${nanoclawDir}/store 0750 nanoclaw nanoclaw -"
    "d ${nanoclawDir}/groups 0750 nanoclaw nanoclaw -"
    "d ${nanoclawDir}/data 0750 nanoclaw nanoclaw -"
    "d ${nanoclawDir}/data/env 0750 nanoclaw nanoclaw -"
    "d ${nanoclawDir}/logs 0750 nanoclaw nanoclaw -"
  ];

  # Git clone/setup service (one-time)
  systemd.services.nanoclaw-git-setup = {
    description = "Clone NanoClaw repository";
    wantedBy = [ "podman-nanoclaw.service" ];
    before = [ "nanoclaw-container-build.service" "nanoclaw-compose-setup.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = nanoclawGitSetup;
    };
  };

  # Generate docker-compose.yml
  systemd.services.nanoclaw-compose-setup = {
    description = "Generate NanoClaw docker-compose configuration";
    wantedBy = [ "podman-nanoclaw.service" ];
    before = [ "podman-nanoclaw.service" ];
    after = [ "nanoclaw-git-setup.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = nanoclawComposeSetup;
    };
  };

  # Generate environment file
  systemd.services.nanoclaw-env = {
    description = "Generate NanoClaw environment configuration";
    wantedBy = [ "podman-nanoclaw.service" ];
    before = [ "podman-nanoclaw.service" ];
    after = [ "ollama.service" "nanoclaw-git-setup.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = nanoclawEnvScript;
    };
  };

  # Build container image (one-time)
  systemd.services.nanoclaw-container-build = {
    description = "Build NanoClaw agent container image";
    wantedBy = [ "podman-nanoclaw.service" ];
    before = [ "podman-nanoclaw.service" ];
    after = [ "nanoclaw-git-setup.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = nanoclawContainerBuild;
      TimeoutStartSec = "30min";
    };
  };

  # NanoClaw main service via podman-compose
  systemd.services.podman-nanoclaw = {
    description = "NanoClaw AI Agent (Discord Bot) via podman-compose";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network.target"
      "podman.socket"
      "ollama.service"
      "ollama-model-loader.service"
      "nanoclaw-env.service"
      "nanoclaw-compose-setup.service"
      "nanoclaw-container-build.service"
      "nanoclaw-git-setup.service"
    ];
    wants = [ "ollama.service" ];
    requires = [ "podman.socket" ];

    path = [ pkgs.podman pkgs.podman-compose pkgs.git ];

    serviceConfig = {
      Type = "simple";
      WorkingDirectory = nanoclawDir;
      # podman-compose pull may fail if network is unavailable, so use '|| true'
      ExecStartPre = "${pkgs.bash}/bin/bash -c '${pkgs.podman-compose}/bin/podman-compose pull || true'";
      ExecStart = "${pkgs.podman-compose}/bin/podman-compose up";
      ExecStop = "${pkgs.podman-compose}/bin/podman-compose down";
      Restart = "on-failure";
      RestartSec = "10s";
      TimeoutStartSec = "10min";
    };
  };

  # Install dependencies and helper scripts
  environment.systemPackages = with pkgs; [
    nodejs_24
    podman
    podman-compose
    git
    nanoclawAddDiscord
  ];
}
