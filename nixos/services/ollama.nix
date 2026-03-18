# Ollama service configuration
# Local LLM runtime for IronClaw

{ config, pkgs, lib, ... }:

{
  services.ollama = {
    enable = true;
    host = "127.0.0.1";
    port = 11434;
    # Model will be pulled manually: ollama pull qwen3.5:4b
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
}
