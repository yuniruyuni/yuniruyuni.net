# =============================================================================
# Cloudflare Variables
# =============================================================================

variable "cloudflare_api_token" {
  description = "Cloudflare API Token"
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare Account ID"
  type        = string
  sensitive   = true
}

variable "zone_name" {
  description = "Cloudflare Zone name (domain)"
  type        = string
  default     = "yuniruyuni.net"
}

variable "vps_ip_address" {
  description = "VPS server IP address"
  type        = string
  sensitive   = true
}

# =============================================================================
# GCP Variables
# =============================================================================

variable "gcp_project_id" {
  description = "GCP Project ID"
  type        = string
  sensitive   = true
}

variable "gcp_region" {
  description = "GCP Region"
  type        = string
  default     = "us-west1"
}

variable "gcp_zone" {
  description = "GCP Zone"
  type        = string
  default     = "us-west1-b"
}

# =============================================================================
# GitHub Variables
# =============================================================================

variable "github_repositories" {
  description = "List of GitHub repositories allowed to deploy via Workload Identity"
  type        = list(string)
  default = [
    "StreamTagInventory",
    "costume",
    "LegendOfManaWeapon",
    "yuniruyuni.net",
    "web",
  ]
}
