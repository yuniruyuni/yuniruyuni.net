# NanoClaw AI agent runtime configuration
# Runs NanoClaw with Ollama backend via Anthropic API compatibility
# Discord Bot integration with container sandboxing

{ config, pkgs, lib, ... }:

let
  # NanoClaw source from GitHub
  nanoclawSrc = pkgs.fetchFromGitHub {
    owner = "qwibitai";
    repo = "nanoclaw";
    rev = "main";
    sha256 = "sha256-g5BeuSxjMDXbkV6Kaks9TwC/xoqGIKWgCgs1VSvSbH0=";
  };

  # Environment file generation script
  nanoclawEnvScript = pkgs.writeShellScript "nanoclaw-env" ''
    DISCORD_TOKEN=$(cat ${config.age.secrets.discord-bot-token.path})
    mkdir -p /var/lib/nanoclaw/data/env
    cat > /var/lib/nanoclaw/.env << EOF
# Discord Bot
DISCORD_BOT_TOKEN=$DISCORD_TOKEN
ASSISTANT_NAME=MrDamian

# Ollama with Anthropic API compatibility
# Main process uses localhost, containers use host.containers.internal
ANTHROPIC_BASE_URL=http://localhost:11434/v1
ANTHROPIC_AUTH_TOKEN=ollama
MODEL=qwen3:4b

# Container settings
CONTAINER_RUNTIME=podman
CONTAINER_IMAGE=nanoclaw-agent:latest
MAX_CONCURRENT_CONTAINERS=2
CONTAINER_TIMEOUT=1800000
EOF
    chmod 600 /var/lib/nanoclaw/.env
    chown -R nanoclaw:nanoclaw /var/lib/nanoclaw

    # Sync to container env
    cp /var/lib/nanoclaw/.env /var/lib/nanoclaw/data/env/env
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
    TMPDIR=$(mktemp -d)
    trap "rm -rf $TMPDIR" EXIT

    cp -r ${nanoclawSrc}/* "$TMPDIR/"
    # Dockerfile expects to run from container/ directory
    cd "$TMPDIR/container"
    ${pkgs.podman}/bin/podman build -t nanoclaw-agent:latest .
    echo "Container image built successfully"
  '';

  # Setup script to initialize NanoClaw
  nanoclawSetup = pkgs.writeShellScript "nanoclaw-setup" ''
    cd /var/lib/nanoclaw

    # Copy source if not present or update if needed
    if [ ! -f "package.json" ]; then
      echo "Initializing NanoClaw from source..."
      cp -r ${nanoclawSrc}/* .
    fi

    # Install dependencies if needed
    if [ ! -d "node_modules" ]; then
      echo "Installing dependencies..."
      export HOME=/var/lib/nanoclaw
      ${pkgs.nodejs_22}/bin/npm ci --production=false
    fi

    # Build if needed
    if [ ! -d "dist" ]; then
      echo "Building NanoClaw..."
      export HOME=/var/lib/nanoclaw
      ${pkgs.nodejs_22}/bin/npm run build
    fi

    # Ensure correct ownership after setup (runs as root)
    chown -R nanoclaw:nanoclaw /var/lib/nanoclaw

    echo "NanoClaw setup complete"
  '';

in
{
  # Create nanoclaw user and group
  users.users.nanoclaw = {
    isSystemUser = true;
    group = "nanoclaw";
    home = "/var/lib/nanoclaw";
    createHome = true;
    extraGroups = [ "podman" ];
    # Required for rootless podman
    subUidRanges = [{ startUid = 100000; count = 65536; }];
    subGidRanges = [{ startGid = 100000; count = 65536; }];
  };
  users.groups.nanoclaw = {};

  # NanoClaw directories
  systemd.tmpfiles.rules = lib.mkAfter [
    "d /var/lib/nanoclaw 0750 nanoclaw nanoclaw -"
    "d /var/lib/nanoclaw/store 0750 nanoclaw nanoclaw -"
    "d /var/lib/nanoclaw/groups 0750 nanoclaw nanoclaw -"
    "d /var/lib/nanoclaw/data 0750 nanoclaw nanoclaw -"
    "d /var/lib/nanoclaw/data/env 0750 nanoclaw nanoclaw -"
    "d /var/lib/nanoclaw/logs 0750 nanoclaw nanoclaw -"
  ];

  # Generate environment file
  systemd.services.nanoclaw-env = {
    description = "Generate NanoClaw environment configuration";
    wantedBy = [ "nanoclaw.service" ];
    before = [ "nanoclaw.service" ];
    after = [ "ollama.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = nanoclawEnvScript;
    };
  };

  # Build container image (one-time)
  systemd.services.nanoclaw-container-build = {
    description = "Build NanoClaw agent container image";
    wantedBy = [ "nanoclaw.service" ];
    before = [ "nanoclaw.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = nanoclawContainerBuild;
      TimeoutStartSec = "30min";
    };
  };

  # NanoClaw main service
  systemd.services.nanoclaw = {
    description = "NanoClaw AI Agent (Discord Bot)";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network.target"
      "ollama.service"
      "ollama-model-loader.service"
      "nanoclaw-env.service"
      "nanoclaw-container-build.service"
    ];
    wants = [ "ollama.service" ];

    path = [ pkgs.nodejs_22 pkgs.podman pkgs.git pkgs.bash pkgs.coreutils ];

    serviceConfig = {
      Type = "simple";
      User = "nanoclaw";
      Group = "nanoclaw";
      SupplementaryGroups = [ "podman" ];
      WorkingDirectory = "/var/lib/nanoclaw";
      EnvironmentFile = "/var/lib/nanoclaw/.env";
      ExecStartPre = "+${nanoclawSetup}";
      ExecStart = "${pkgs.nodejs_22}/bin/node dist/index.js";
      Restart = "on-failure";
      RestartSec = "10s";

      # Use root podman via socket (container images are built as root)
      # CONTAINER_HOST is the correct env var for podman (not DOCKER_HOST)
      Environment = [
        "CONTAINER_HOST=unix:///run/podman/podman.sock"
      ];

      # Security hardening
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      ReadWritePaths = [ "/var/lib/nanoclaw" ];
    };
  };

  # Install Node.js 22 and other dependencies
  environment.systemPackages = with pkgs; [
    nodejs_22
    podman
  ];
}
