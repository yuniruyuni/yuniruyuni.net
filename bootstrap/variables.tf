variable "project_id" {
  description = "GCP Project ID"
  type        = string
  default     = "yuniruyuni-net"
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "asia-northeast1"
}

variable "github_org" {
  description = "GitHub organization or user name"
  type        = string
  default     = "yuniruyuni"
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = "yuniruyuni.net"
}
