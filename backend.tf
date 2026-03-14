terraform {
  backend "gcs" {
    bucket = "yuniruyuni-net-terraform-state"
    prefix = "infrastructure"
  }
}
