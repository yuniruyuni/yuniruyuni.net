# Secrets configuration using agenix
# Secrets are encrypted with age and decrypted at runtime

{ config, ... }:

{
  # Define secrets - these will be decrypted to /run/agenix/
  age.secrets = {
    cloudflared-token = {
      file = ./secrets/cloudflared-token.age;
      owner = "cloudflared";
      group = "cloudflared";
      mode = "0400";
    };

    n8n-encryption-key = {
      file = ./secrets/n8n-encryption-key.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };

    mackerel-api-key = {
      file = ./secrets/mackerel-api-key.age;
      owner = "mackerel-agent";
      group = "mackerel-agent";
      mode = "0400";
    };

    rclone-config = {
      file = ./secrets/rclone-config.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };

    ironclaw-db-password = {
      file = ./secrets/ironclaw-db-password.age;
      owner = "postgres";
      group = "postgres";
      mode = "0400";
    };
  };
}
