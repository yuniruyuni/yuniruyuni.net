# Ollama service configuration
# Local LLM runtime for IronClaw

{ config, pkgs, lib, ... }:

{
  services.ollama = {
    enable = true;
    host = "127.0.0.1";
    port = 11434;

    # Qwen 3.5 4B - multimodal model with tool calling support
    loadModels = [ "qwen3.5:4b" ];
  };

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
