# =============================================================================
# GCP Provider
# =============================================================================

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

# =============================================================================
# Locals (shared configuration)
# =============================================================================

locals {
  # Required GCP APIs
  required_apis = toset([
    "run.googleapis.com",
    "compute.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "artifactregistry.googleapis.com",
    "secretmanager.googleapis.com",
    "storage.googleapis.com",              # state bucket + SM usage
    "cloudresourcemanager.googleapis.com", # project-level IAM management
  ])

  # Cloud Run services configuration
  # hostname = "" means root domain (yuniruyuni.net)
  cloud_run_services = {
    costume              = { name = "costume", hostname = "costume" }
    lom                  = { name = "lom", hostname = "lom" }
    stream_tag_inventory = { name = "stream-tag-inventory", hostname = "tags" }
    web                  = { name = "web", hostname = "" }
    template             = { name = "template", hostname = "template" }
  }

  # DB-enabled apps: each gets 2 secrets (app password + admin password)
  # New app: add one entry here
  db_apps = {
    stream_tag_inventory = {
      service_name = "stream-tag-inventory"
    }
    template = {
      service_name = "template"
    }
  }

  # GitHub Apps Deployer roles
  github_deployer_roles = toset([
    "roles/run.developer",
    "roles/iam.serviceAccountUser",
    "roles/artifactregistry.writer",
    "roles/secretmanager.viewer",
  ])
}

# =============================================================================
# Enable Required APIs (consolidated with for_each)
# =============================================================================

resource "google_project_service" "required" {
  for_each           = local.required_apis
  service            = each.value
  disable_on_destroy = false
}

# =============================================================================
# Artifact Registry (for Cloud Run container images)
# =============================================================================

resource "google_artifact_registry_repository" "apps" {
  location      = var.gcp_region
  repository_id = "apps"
  description   = "Container images for Cloud Run apps"
  format        = "DOCKER"

  # Keep only the 3 most recent versions per image to stay within 500MB free tier
  cleanup_policies {
    id     = "keep-recent-versions"
    action = "KEEP"
    most_recent_versions {
      keep_count = 3
    }
  }

  cleanup_policies {
    id     = "delete-old-images"
    action = "DELETE"
    condition {
      older_than = "604800s" # 7 days
    }
  }

  depends_on = [google_project_service.required]
}

# =============================================================================
# Workload Identity for GitHub Actions
# =============================================================================

resource "google_iam_workload_identity_pool" "github_actions" {
  workload_identity_pool_id = "github-actions-pool"
  display_name              = "GitHub Actions Pool"
  description               = "Pool for GitHub Actions across multiple repositories"
}

resource "google_iam_workload_identity_pool_provider" "github_actions" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_actions.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-actions-provider"
  display_name                       = "GitHub Actions Provider"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
    "attribute.owner"      = "assertion.repository_owner"
  }

  attribute_condition = <<-EOT
    assertion.repository_owner == "yuniruyuni" &&
    assertion.repository in [${join(", ", [for r in var.github_repositories : "\"yuniruyuni/${r}\""])}]
  EOT

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# =============================================================================
# Service Accounts
# =============================================================================

# GitHub Apps Deployer (for app repositories)
resource "google_service_account" "github_apps_deployer" {
  account_id   = "github-apps-deployer"
  display_name = "GitHub Apps Deployer"
  description  = "Service account for deploying apps from GitHub Actions"
}

resource "google_service_account_iam_member" "github_apps_deployer_workload_identity" {
  service_account_id = google_service_account.github_apps_deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_actions.name}/attribute.owner/yuniruyuni"
}

# GitHub Apps Deployer IAM roles (consolidated with for_each)
resource "google_project_iam_member" "github_apps_deployer" {
  for_each = local.github_deployer_roles
  project  = var.gcp_project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.github_apps_deployer.email}"
}

# Tunnel Gateway (for GCE to invoke Cloud Run)
resource "google_service_account" "tunnel_gateway" {
  account_id   = "tunnel-gateway"
  display_name = "Tunnel Gateway"
  description  = "Service account for GCE tunnel gateway to invoke Cloud Run"
}

# google-startup-scripts-runner flushes startup-script output to Cloud Logging.
# Without logWriter it runs with "permission denied" warnings that obscure
# real errors. The GSM secret access is already scoped via a per-secret
# secretAccessor binding, so adding project-level logWriter doesn't widen the
# blast radius in any meaningful way.
resource "google_project_iam_member" "tunnel_gateway_logwriter" {
  project = var.gcp_project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.tunnel_gateway.email}"
}

# =============================================================================
# VPC Network with Private Google Access
# =============================================================================

resource "google_compute_network" "main" {
  name                    = "main-vpc"
  auto_create_subnetworks = false

  depends_on = [google_project_service.required]
}

resource "google_compute_subnetwork" "main" {
  name                     = "main-subnet"
  ip_cidr_range            = "10.0.0.0/24"
  region                   = var.gcp_region
  network                  = google_compute_network.main.id
  private_ip_google_access = true # Enable Private Google Access for Cloud Run internal access
}

# Allow egress for Cloudflare tunnel (HTTPS + QUIC tunnel ports only)
resource "google_compute_firewall" "allow_egress" {
  name    = "allow-egress"
  network = google_compute_network.main.id

  direction = "EGRESS"
  priority  = 1000

  allow {
    protocol = "tcp"
    ports    = ["443", "7844"]
  }

  allow {
    protocol = "udp"
    ports    = ["7844"]
  }

  destination_ranges = ["0.0.0.0/0"]
}

# =============================================================================
# GCE Tunnel Gateway (Container-Optimized OS + cloudflared container)
# =============================================================================

resource "google_compute_instance" "tunnel_gateway" {
  name         = "tunnel-gateway"
  machine_type = "e2-micro"
  zone         = var.gcp_zone

  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = "cos-cloud/cos-stable"
      size  = 10 # GB (無料枠: 30GB)
    }
  }

  network_interface {
    network    = google_compute_network.main.id
    subnetwork = google_compute_subnetwork.main.id
    # 外部IP付与 - コンテナイメージpull用 + Cloudflare接続用
    access_config {
      # Ephemeral external IP
    }
  }

  metadata = {
    # Token is fetched at boot from Secret Manager instead of being baked into
    # instance metadata. plan SA has compute viewer (can read metadata) but
    # lacks secretmanager.secretAccessor on the tunnel-token secret, so the
    # metadata side-channel that previously exposed the token is closed.
    startup-script = templatefile("${path.module}/scripts/cloudflared-boot.sh.tftpl", {
      project_id      = var.gcp_project_id
      secret_name     = google_secret_manager_secret.gce_tunnel_token.secret_id
      cloudflared_img = "cloudflare/cloudflared:2026.3.0"
    })
    google-logging-enabled = "true"
  }

  service_account {
    email = google_service_account.tunnel_gateway.email
    # cloud-platform is required so the instance can exchange its SA identity
    # for an access token against Secret Manager. Authorization is still gated
    # by IAM on the specific secret (see gce_tunnel_token_accessor).
    scopes = ["cloud-platform"]
  }

  scheduling {
    preemptible       = false
    automatic_restart = true
  }

  labels = {
    purpose      = "tunnel-gateway"
    tier         = "free"
    container-vm = "cos-stable"
  }

  depends_on = [
    google_project_service.required,
    # Ensure the secret + IAM binding exist before the instance boots and
    # tries to fetch from Secret Manager via its startup-script.
    google_secret_manager_secret_version.gce_tunnel_token,
    google_secret_manager_secret_iam_member.gce_tunnel_token_accessor,
  ]
}

# =============================================================================
# Secret Manager (GCE tunnel token — fetched at boot, not baked into metadata)
# =============================================================================

resource "google_secret_manager_secret" "gce_tunnel_token" {
  secret_id = "gce-tunnel-token"

  replication {
    auto {}
  }

  depends_on = [google_project_service.required]
}

resource "google_secret_manager_secret_version" "gce_tunnel_token" {
  secret      = google_secret_manager_secret.gce_tunnel_token.id
  secret_data = local.gce_tunnel_token
}

# Only the tunnel-gateway instance's SA can read this secret. plan SA (viewer)
# has no secretmanager.secretAccessor, so a plan-SA token leak cannot escalate
# into tunnel impersonation through this path.
resource "google_secret_manager_secret_iam_member" "gce_tunnel_token_accessor" {
  secret_id = google_secret_manager_secret.gce_tunnel_token.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.tunnel_gateway.email}"
}

# =============================================================================
# Cloud Run Data Sources (consolidated with for_each)
# =============================================================================

data "google_cloud_run_service" "services" {
  for_each = local.cloud_run_services
  name     = each.value.name
  location = var.gcp_region
}

# =============================================================================
# Cloud Run Invoker (consolidated with for_each)
# =============================================================================

# With ingress: internal, traffic is restricted to VPC only
# allUsers IAM allows unauthenticated requests from within the VPC
# (cloudflared doesn't add auth headers, so allUsers is still needed)
resource "google_cloud_run_service_iam_member" "public_invoker" {
  for_each = local.cloud_run_services
  location = var.gcp_region
  service  = each.value.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# =============================================================================
# Secret Manager (for Cloud Run database credentials)
# =============================================================================

# Owner/migration DB password (DDL) — one per db_app
resource "google_secret_manager_secret" "db_password" {
  for_each  = local.db_apps
  secret_id = "${each.value.service_name}-db-password"

  replication {
    auto {}
  }

  depends_on = [google_project_service.required]
}

# App DB password (DML only) — one per db_app
resource "google_secret_manager_secret" "db_app_password" {
  for_each  = local.db_apps
  secret_id = "${each.value.service_name}-db-app-password"

  replication {
    auto {}
  }

  depends_on = [google_project_service.required]
}

# Grant Cloud Run SA access to both secrets
resource "google_secret_manager_secret_iam_member" "db_password_accessor" {
  for_each  = local.db_apps
  secret_id = google_secret_manager_secret.db_password[each.key].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${data.google_cloud_run_service.services[each.key].template[0].spec[0].service_account_name}"
}

resource "google_secret_manager_secret_iam_member" "db_app_password_accessor" {
  for_each  = local.db_apps
  secret_id = google_secret_manager_secret.db_app_password[each.key].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${data.google_cloud_run_service.services[each.key].template[0].spec[0].service_account_name}"
}

# =============================================================================
# Secret Manager (Cloudflare Access service token for DB tunnel)
# =============================================================================

resource "google_secret_manager_secret" "cf_db_access_client_id" {
  secret_id = "cf-db-access-client-id"

  replication {
    auto {}
  }

  depends_on = [google_project_service.required]
}

resource "google_secret_manager_secret_version" "cf_db_access_client_id" {
  secret      = google_secret_manager_secret.cf_db_access_client_id.id
  secret_data = cloudflare_zero_trust_access_service_token.cloud_run_db.client_id
}

resource "google_secret_manager_secret" "cf_db_access_client_secret" {
  secret_id = "cf-db-access-client-secret"

  replication {
    auto {}
  }

  depends_on = [google_project_service.required]
}

resource "google_secret_manager_secret_version" "cf_db_access_client_secret" {
  secret      = google_secret_manager_secret.cf_db_access_client_secret.id
  secret_data = cloudflare_zero_trust_access_service_token.cloud_run_db.client_secret
}

# Grant all DB-enabled Cloud Run SAs access to the service token secrets
resource "google_secret_manager_secret_iam_member" "cf_db_client_id_accessor" {
  for_each  = local.db_apps
  secret_id = google_secret_manager_secret.cf_db_access_client_id.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${data.google_cloud_run_service.services[each.key].template[0].spec[0].service_account_name}"
}

resource "google_secret_manager_secret_iam_member" "cf_db_client_secret_accessor" {
  for_each  = local.db_apps
  secret_id = google_secret_manager_secret.cf_db_access_client_secret.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${data.google_cloud_run_service.services[each.key].template[0].spec[0].service_account_name}"
}

