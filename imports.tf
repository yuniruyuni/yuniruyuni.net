# One-time imports for existing Cloudflare resources
# Remove these blocks after successful terraform apply

import {
  to = cloudflare_zero_trust_access_application.n8n_webhook
  id = "zones/a8bf81c5ba84f1cb4c64953af0ddb1d8/3ca26a2c-d5ae-4220-9e3f-a5057ad1679d"
}

import {
  to = cloudflare_zero_trust_access_policy.n8n_webhook_bypass
  id = "9c274c96fde0997617734ce5c14ca3da/156388bf-0b62-4683-b5cd-b656f49f9235"
}
