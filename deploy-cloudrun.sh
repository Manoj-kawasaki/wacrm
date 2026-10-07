#!/usr/bin/env bash
set -e

# ============================================================
# WACRM - Automated Google Cloud Run Deployment Script
# ============================================================

# 1. Ensure gcloud is available on PATH
if ! command -v gcloud &> /dev/null; then
  if [ -f "$HOME/google-cloud-sdk/path.bash.inc" ]; then
    # shellcheck source=/dev/null
    source "$HOME/google-cloud-sdk/path.bash.inc"
  elif [ -x "$HOME/google-cloud-sdk/bin/gcloud" ]; then
    export PATH="$HOME/google-cloud-sdk/bin:$PATH"
  elif [ -x "/home/manojpk/google-cloud-sdk/bin/gcloud" ]; then
    export PATH="/home/manojpk/google-cloud-sdk/bin:$PATH"
  fi
fi

if ! command -v gcloud &> /dev/null; then
  echo "❌ Error: Google Cloud CLI (gcloud) not found."
  echo "Please run: source ~/.bashrc"
  exit 1
fi

PROJECT_ID=${1:-$(gcloud config get-value project 2>/dev/null)}
REGION=${2:-"asia-south1"}
SERVICE_NAME="wacrm"

# Resolve exact Project ID if project name or partial name was provided
if [ -n "$PROJECT_ID" ] && [ "$PROJECT_ID" != "(unset)" ]; then
  RESOLVED_ID=$(gcloud projects list --filter="NAME='$PROJECT_ID' OR PROJECT_ID='$PROJECT_ID'" --format="value(PROJECT_ID)" 2>/dev/null | head -n 1 || true)
  if [ -n "$RESOLVED_ID" ]; then
    PROJECT_ID="$RESOLVED_ID"
  fi
fi

if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "(unset)" ]; then
  echo "❌ Error: Google Cloud Project ID is not set."
  echo "Usage: ./deploy-cloudrun.sh <GCP_PROJECT_ID> [REGION]"
  echo "Example: ./deploy-cloudrun.sh cloudzap-wacrm-510805 asia-south1"
  exit 1
fi

# 2. Check if logged in to Google Cloud
ACTIVE_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null || true)
if [ -z "$ACTIVE_ACCOUNT" ]; then
  echo "⚠️ No active Google Cloud account detected."
  echo "👉 Starting authentication. Please log in with your Google Cloud account..."
  gcloud auth login
fi

echo "🚀 Deploying WACRM to Google Cloud Run..."
echo "📦 Project ID: $PROJECT_ID"
echo "📍 Region:     $REGION"
echo "🛠 Service:    $SERVICE_NAME"

# Set active project
gcloud config set project "$PROJECT_ID" --quiet

# 3. Enable required Google Cloud APIs
echo "⚙️ Enabling Cloud Run, Cloud Build, and Artifact Registry APIs..."
if ! gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com --project="$PROJECT_ID"; then
  echo ""
  echo "❌ Failed to enable Cloud Run APIs. Google Cloud requires billing to be enabled on '$PROJECT_ID'."
  echo "👉 Link an active billing account here: https://console.cloud.google.com/billing/linkedaccount?project=$PROJECT_ID"
  exit 1
fi

# 4. Prepare environment variables
ENV_FILE=".env.local"
if [ ! -f "$ENV_FILE" ]; then
  ENV_FILE=".env.local.example"
fi

TEMP_ENV_YAML="/tmp/wacrm-env-$$.yaml"
trap 'rm -f "$TEMP_ENV_YAML"' EXIT

echo "📝 Preparing runtime environment variables from $ENV_FILE..."
if [ -f "$ENV_FILE" ]; then
  grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$ENV_FILE" | while IFS='=' read -r key val; do
    # Strip carriage returns and leading/trailing quotes
    clean_val=$(echo "$val" | tr -d '\r' | sed -e 's/^"//' -e 's/"$//')
    echo "${key}: \"${clean_val}\"" >> "$TEMP_ENV_YAML"
  done
fi

# 5. Build and deploy container to Cloud Run
echo "☁️ Building and deploying container to Cloud Run (Google Cloud Build will compile Dockerfile)..."
if [ -s "$TEMP_ENV_YAML" ]; then
  gcloud run deploy "$SERVICE_NAME" \
    --source . \
    --project "$PROJECT_ID" \
    --region "$REGION" \
    --platform managed \
    --allow-unauthenticated \
    --port 8080 \
    --memory 1Gi \
    --cpu 1 \
    --min-instances 0 \
    --max-instances 5 \
    --env-vars-file "$TEMP_ENV_YAML"
else
  gcloud run deploy "$SERVICE_NAME" \
    --source . \
    --project "$PROJECT_ID" \
    --region "$REGION" \
    --platform managed \
    --allow-unauthenticated \
    --port 8080 \
    --memory 1Gi \
    --cpu 1 \
    --min-instances 0 \
    --max-instances 5
fi

echo ""
echo "============================================================"
echo "🎉 WACRM successfully deployed to Google Cloud Run!"
SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" --project "$PROJECT_ID" --region "$REGION" --format='value(status.url)' 2>/dev/null || echo "")
echo "🔗 Live Service URL: $SERVICE_URL"
echo "============================================================"
