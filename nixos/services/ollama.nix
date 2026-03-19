# Ollama service configuration
# Local LLM runtime with models for n8n integration

{ config, pkgs, lib, ... }:

{
  services.ollama = {
    enable = true;
    # Bind to all interfaces for container access
    host = "0.0.0.0";
    port = 11434;

    # Available models:
    # - fuukeidaisuki/qwen3-swallow-v0.2:8b-rl - Best Japanese 8B model (Tokyo Tech + AIST)
    # - gemma3:4b - Japanese support, 140+ languages, good quality
    # - smollm2:1.7b - lightweight, fast CPU inference, English-focused
    loadModels = [ "fuukeidaisuki/qwen3-swallow-v0.2:8b-rl" "gemma3:4b" "smollm2:1.7b" ];
  };

  # Allow Podman containers to access Ollama
  # Using extraInputRules for nftables compatibility (podman+ wildcard doesn't work)
  networking.firewall.extraInputRules = ''
    # Allow Ollama access from Podman default network (10.88.0.0/16)
    ip saddr 10.88.0.0/16 tcp dport 11434 accept
    # Allow Ollama access from rootless Podman slirp4netns (10.0.2.0/24)
    ip saddr 10.0.2.0/24 tcp dport 11434 accept
  '';

  # Resource constraints for CPU-only VPS
  systemd.services.ollama = {
    serviceConfig = {
      Environment = [
        "OLLAMA_NUM_PARALLEL=1"
        "OLLAMA_MAX_LOADED_MODELS=1"
      ];
    };
  };

  # Wait for ollama API to be ready before loading models
  systemd.services.ollama-model-loader = {
    serviceConfig = {
      ExecStartPre = pkgs.writeShellScript "wait-for-ollama" ''
        echo "Waiting for Ollama API to be ready..."
        for i in $(seq 1 30); do
          if ${pkgs.curl}/bin/curl -s http://127.0.0.1:11434/api/tags > /dev/null 2>&1; then
            echo "Ollama API is ready"
            exit 0
          fi
          echo "Attempt $i/30: Ollama not ready, waiting..."
          sleep 2
        done
        echo "Ollama API did not become ready in time"
        exit 1
      '';
    };
  };
}
