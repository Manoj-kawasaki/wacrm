#!/usr/bin/env bash
set -e

# ============================================================
# WACRM - Automated Google Cloud Run Deployment Script
# ============================================================

PROJECT_ID=${1:-$(gcloud config get-value project 2>/dev/null)}
REGION=${2:-"asia-south1"}
SERVICE_NAME="wacrm"

if [ -z "$PROJECT_ID" ]; then
  echo "❌ Error: Google Cloud Project ID is not set."
  echo "Usage: ./deploy-cloudrun.sh <GCP_PROJECT_ID> [REGION]"
  echo "Example: ./deploy-cloudrun.sh my-gcp-project asia-south1"
  exit 1
fi

echo "🚀 Deploying WACRM to Google Cloud Run..."
echo "📦 Project ID: $PROJECT_ID"
echo "📍 Region:     $REGION"
echo "🛠 Service:    $SERVICE_NAME"

# Enable required Google Cloud APIs
echo "⚙️ Enabling Cloud Run and Cloud Build APIs..."
gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com --project="$PROJECT_ID"

# Read environment variables from .env.local if present
ENV_VARS_FILE=".env.local"
if [ ! -f "$ENV_VARS_FILE" ]; then
  echo "⚠️ Warning: .env.local not found, using .env.local.example"
  ENV_VARS_FILE=".env.local.example"
fi

# Deploy directly via gcloud source deploy (Cloud Build builds the Dockerfile in the cloud)
echo "☁️ Building and deploying container to Cloud Run..."
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
  --env-vars-file <(grep -v '^#' "$ENV_VARS_FILE" | grep -v '^[[:space:]]*$' | sed 's/=\(.*\)/: "\1"/' | sed 's/^[[:space:]]*/  /') || \
gcloud run deploy "$SERVICE_NAME" \
  --source . \
  --project "$PROJECT_ID" \
  --region "$REGION" \
  --platform managed \
  --allow-unauthenticated \
  --port 8080

echo "✅ Deployment complete!"
gcloud run services describe "$SERVICE_NAME" --project "$PROJECT_ID" --region "$REGION" --format='value(status.url)'
