# Ollama service for local LLM inference
# Provides LFM2.5 models to n8n (via host.containers.internal)
# and to Cloud Run apps (via Cloudflare Tunnel + Access Service Token)

{ config, pkgs, lib, ... }:

{
  services.ollama = {
    enable = true;

    # Bind to all interfaces so:
    #  - cloudflared (host process) can reach via localhost
    #  - n8n Podman container can reach via host.containers.internal
    # External access is blocked by firewall (allowedTCPPorts = [])
    host = "0.0.0.0";
    port = 11434;

    home = "/var/lib/ollama";

    # CPU-only VPS — no GPU acceleration
    acceleration = false;

    # Declaratively pull these models on first start
    # LFM2.5 series: hybrid attention + convolution, CPU-optimized
    loadModels = [
      "hadad/LFM2.5-1.2B:Q4_K_M"          # 731MB, 1.2B params
      "jewelzufo/LFM2.5-350M-GGUF:latest" # 267MB, 350M params
    ];
  };
}
