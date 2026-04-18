#!/bin/bash
# One-shot bootstrap for this terraform-managed GCP project.
#
# Phase A: gcloud creates the minimum set of resources terraform cannot create
#          for itself (state bucket, CI service accounts, WIF pool/provider,
#          and their IAM bindings).
# Phase B: terraform init + import pulls those gcloud-created resources into
#          the main state, so every subsequent change happens via the normal
#          PR -> code owner review -> CI apply flow.
#
# Idempotent: safe to re-run on an existing environment (gcloud steps are
# no-ops when resources already exist; terraform imports are skipped if the
# address is already in state).
#
# Prerequisites:
#   - gcloud authenticated as an account with Owner (or equivalent) on the
#     target project
#   - terraform >= 1.5 available on $PATH
#   - ADC set up for terraform to talk to GCS (gcloud auth application-default
#     login) — terraform reads these even when impersonating is not used
#
# Usage:
#   PROJECT=yuniruyuni-net GITHUB_ORG=yuniruyuni GITHUB_REPO=yuniruyuni.net \
#     scripts/bootstrap.sh

set -euo pipefail

PROJECT="${PROJECT:-yuniruyuni-net}"
REGION="${REGION:-asia-northeast1}"
GITHUB_ORG="${GITHUB_ORG:-yuniruyuni}"
GITHUB_REPO="${GITHUB_REPO:-yuniruyuni.net}"

BUCKET="${PROJECT}-terraform-state"
APPLY_SA_ID="terraform-github"
APPLY_SA="${APPLY_SA_ID}@${PROJECT}.iam.gserviceaccount.com"
PLAN_SA_ID="terraform-github-plan"
PLAN_SA="${PLAN_SA_ID}@${PROJECT}.iam.gserviceaccount.com"
POOL_ID="github-actions"
PROVIDER_ID="github"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

log()  { printf '\033[1;34m[bootstrap]\033[0m %s\n' "$*"; }
skip() { printf '\033[1;33m[skip]\033[0m %s\n' "$*"; }

# ============================================================================
# Phase A: gcloud — create the minimum set of bootstrap resources
# ============================================================================

log "Phase A: ensuring gcloud-level prerequisites on project '$PROJECT'"

# APIs
log "enabling APIs"
gcloud services enable \
  storage.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  cloudresourcemanager.googleapis.com \
  --project="$PROJECT"

# State bucket
if gcloud storage buckets describe "gs://$BUCKET" --project="$PROJECT" &>/dev/null; then
  skip "state bucket gs://$BUCKET already exists"
else
  log "creating state bucket gs://$BUCKET"
  gcloud storage buckets create "gs://$BUCKET" \
    --project="$PROJECT" \
    --location="$REGION" \
    --uniform-bucket-level-access \
    --public-access-prevention
  gcloud storage buckets update "gs://$BUCKET" --versioning --project="$PROJECT"
fi

# Apply SA
if gcloud iam service-accounts describe "$APPLY_SA" --project="$PROJECT" &>/dev/null; then
  skip "apply SA $APPLY_SA already exists"
else
  log "creating apply SA $APPLY_SA"
  gcloud iam service-accounts create "$APPLY_SA_ID" \
    --project="$PROJECT" \
    --display-name="Terraform GitHub Actions" \
    --description="Service account for Terraform apply from GitHub Actions"
fi

log "binding apply SA project-level roles (idempotent)"
for role in roles/editor roles/iam.securityAdmin roles/iam.workloadIdentityPoolAdmin; do
  gcloud projects add-iam-policy-binding "$PROJECT" \
    --member="serviceAccount:${APPLY_SA}" \
    --role="$role" \
    --condition=None >/dev/null
done

log "granting apply SA objectAdmin on state bucket"
gcloud storage buckets add-iam-policy-binding "gs://$BUCKET" \
  --member="serviceAccount:${APPLY_SA}" \
  --role="roles/storage.objectAdmin" >/dev/null

# Plan SA
if gcloud iam service-accounts describe "$PLAN_SA" --project="$PROJECT" &>/dev/null; then
  skip "plan SA $PLAN_SA already exists"
else
  log "creating plan SA $PLAN_SA"
  gcloud iam service-accounts create "$PLAN_SA_ID" \
    --project="$PROJECT" \
    --display-name="Terraform GitHub Actions (Plan)" \
    --description="Read-only service account for terraform plan from GitHub Actions"
fi

log "binding plan SA project-level roles (idempotent)"
for role in roles/viewer roles/iam.securityReviewer; do
  gcloud projects add-iam-policy-binding "$PROJECT" \
    --member="serviceAccount:${PLAN_SA}" \
    --role="$role" \
    --condition=None >/dev/null
done

log "granting plan SA objectViewer on state bucket"
gcloud storage buckets add-iam-policy-binding "gs://$BUCKET" \
  --member="serviceAccount:${PLAN_SA}" \
  --role="roles/storage.objectViewer" >/dev/null

# WIF pool
if gcloud iam workload-identity-pools describe "$POOL_ID" \
    --location=global --project="$PROJECT" &>/dev/null; then
  skip "WIF pool $POOL_ID already exists"
else
  log "creating WIF pool $POOL_ID"
  gcloud iam workload-identity-pools create "$POOL_ID" \
    --project="$PROJECT" --location=global \
    --display-name="GitHub Actions" \
    --description="Workload Identity Pool for Terraform CI (apply / plan SAs)"
fi

# WIF provider
if gcloud iam workload-identity-pools providers describe "$PROVIDER_ID" \
    --workload-identity-pool="$POOL_ID" --location=global \
    --project="$PROJECT" &>/dev/null; then
  skip "WIF provider $PROVIDER_ID already exists"
else
  log "creating WIF provider $PROVIDER_ID"
  gcloud iam workload-identity-pools providers create-oidc "$PROVIDER_ID" \
    --workload-identity-pool="$POOL_ID" \
    --project="$PROJECT" --location=global \
    --display-name="GitHub" \
    --description="GitHub OIDC Provider for Terraform CI" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository" \
    --attribute-condition="assertion.repository_owner == '${GITHUB_ORG}'"
fi

POOL_NAME="$(gcloud iam workload-identity-pools describe "$POOL_ID" \
  --project="$PROJECT" --location=global --format='value(name)')"

log "binding GitHub repo ${GITHUB_ORG}/${GITHUB_REPO} to apply SA via WIF"
gcloud iam service-accounts add-iam-policy-binding "$APPLY_SA" \
  --project="$PROJECT" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/${POOL_NAME}/attribute.repository/${GITHUB_ORG}/${GITHUB_REPO}" >/dev/null

log "binding GitHub repo ${GITHUB_ORG}/${GITHUB_REPO} to plan SA via WIF"
gcloud iam service-accounts add-iam-policy-binding "$PLAN_SA" \
  --project="$PROJECT" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/${POOL_NAME}/attribute.repository/${GITHUB_ORG}/${GITHUB_REPO}" >/dev/null

# ============================================================================
# Phase B: terraform init + import
# ============================================================================

log "Phase B: initializing terraform and importing bootstrap resources"

cd "$REPO_ROOT"

export TF_VAR_gcp_project_id="$PROJECT"
# Provide dummy values for other required TF_VAR_* that terraform init /
# import may evaluate. Values are not actually used during import since
# import only needs the resource ID.
export TF_VAR_cloudflare_api_token="${TF_VAR_cloudflare_api_token:-dummy}"
export TF_VAR_cloudflare_account_id="${TF_VAR_cloudflare_account_id:-dummy}"
export TF_VAR_vps_ip_address="${TF_VAR_vps_ip_address:-0.0.0.0}"
export TF_VAR_owner_email="${TF_VAR_owner_email:-dummy@example.com}"
export TF_VAR_google_oauth_client_id="${TF_VAR_google_oauth_client_id:-dummy}"
export TF_VAR_google_oauth_client_secret="${TF_VAR_google_oauth_client_secret:-dummy}"

terraform init -input=false

import_if_missing() {
  local addr="$1"
  local id="$2"
  if terraform state show "$addr" >/dev/null 2>&1; then
    skip "$addr already in state"
  else
    log "importing $addr <- $id"
    terraform import -input=false "$addr" "$id"
  fi
}

# Bucket / APIs
import_if_missing 'google_storage_bucket.terraform_state' \
  "$BUCKET"
import_if_missing 'google_project_service.required["storage.googleapis.com"]' \
  "$PROJECT/storage.googleapis.com"
import_if_missing 'google_project_service.required["cloudresourcemanager.googleapis.com"]' \
  "$PROJECT/cloudresourcemanager.googleapis.com"
import_if_missing 'google_project_service.required["iam.googleapis.com"]' \
  "$PROJECT/iam.googleapis.com"
import_if_missing 'google_project_service.required["iamcredentials.googleapis.com"]' \
  "$PROJECT/iamcredentials.googleapis.com"

# Apply SA
import_if_missing 'google_service_account.terraform_github' \
  "projects/${PROJECT}/serviceAccounts/${APPLY_SA}"
for role in roles/editor roles/iam.securityAdmin roles/iam.workloadIdentityPoolAdmin; do
  import_if_missing "google_project_iam_member.terraform_github[\"$role\"]" \
    "$PROJECT $role serviceAccount:${APPLY_SA}"
done
import_if_missing 'google_storage_bucket_iam_member.terraform_state_admin' \
  "b/${BUCKET} roles/storage.objectAdmin serviceAccount:${APPLY_SA}"

# Plan SA
import_if_missing 'google_service_account.terraform_github_plan' \
  "projects/${PROJECT}/serviceAccounts/${PLAN_SA}"
for role in roles/viewer roles/iam.securityReviewer; do
  import_if_missing "google_project_iam_member.terraform_github_plan[\"$role\"]" \
    "$PROJECT $role serviceAccount:${PLAN_SA}"
done
import_if_missing 'google_storage_bucket_iam_member.terraform_state_plan' \
  "b/${BUCKET} roles/storage.objectViewer serviceAccount:${PLAN_SA}"

# WIF
import_if_missing 'google_iam_workload_identity_pool.ci' \
  "projects/${PROJECT}/locations/global/workloadIdentityPools/${POOL_ID}"
import_if_missing 'google_iam_workload_identity_pool_provider.ci_github' \
  "projects/${PROJECT}/locations/global/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}"
import_if_missing 'google_service_account_iam_member.workload_identity_user_apply' \
  "projects/${PROJECT}/serviceAccounts/${APPLY_SA} roles/iam.workloadIdentityUser principalSet://iam.googleapis.com/${POOL_NAME}/attribute.repository/${GITHUB_ORG}/${GITHUB_REPO}"
import_if_missing 'google_service_account_iam_member.workload_identity_user_plan' \
  "projects/${PROJECT}/serviceAccounts/${PLAN_SA} roles/iam.workloadIdentityUser principalSet://iam.googleapis.com/${POOL_NAME}/attribute.repository/${GITHUB_ORG}/${GITHUB_REPO}"

# ============================================================================
# Summary
# ============================================================================

cat <<EOF

=========================================================================
Bootstrap complete.

GitHub secrets to configure (Environments: plan / apply):

  GCP_PROJECT_ID                 = ${PROJECT}
  GCP_WORKLOAD_IDENTITY_PROVIDER = ${POOL_NAME}/providers/${PROVIDER_ID}
  GCP_SERVICE_ACCOUNT (plan)     = ${PLAN_SA}
  GCP_SERVICE_ACCOUNT (apply)    = ${APPLY_SA}

Next: push this repo; CI will 'terraform apply' and reconcile state with
the main HCL (this may narrow/adjust roles to match HCL).
=========================================================================
EOF
