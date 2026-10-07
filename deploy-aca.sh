#!/usr/bin/env bash
set -e

# ============================================================
# WACRM - Automated Azure Container Apps Deployment Script
# ============================================================

RESOURCE_GROUP=${1:-"cloudzap-wacrm-rg"}
LOCATION=${2:-"centralindia"}
ENVIRONMENT_NAME=${3:-"cloudzap-wacrm-env"}
APP_NAME="wacrm"
REGISTRY_NAME="cloudzapwacrm$((RANDOM % 9000 + 1000))"

echo "============================================================"
echo "🚀 Deploying WACRM to Azure Container Apps"
echo "============================================================"
echo "📦 Resource Group:  $RESOURCE_GROUP"
echo "📍 Azure Region:    $LOCATION"
echo "🌐 Environment:     $ENVIRONMENT_NAME"
echo "🛠 Container App:   $APP_NAME"
echo "⚓ Target Port:     3000"
echo "⚖️ Replicas:        Min 0 (scale-to-zero) / Max 2"
echo ""

# 1. Verify Azure CLI is installed
if ! command -v az &> /dev/null; then
  echo "❌ Error: Azure CLI ('az') not found."
  echo "Please install Azure CLI or run from Windows PowerShell: .\deploy-aca.ps1"
  exit 1
fi

# 2. Check Authentication
echo "🔐 Verifying Azure CLI authentication..."
if ! az account show &> /dev/null; then
  echo "⚠️ Not logged in to Azure. Running 'az login'..."
  az login
fi
ACTIVE_SUB=$(az account show --query "name" -o tsv)
ACTIVE_USER=$(az account show --query "user.name" -o tsv)
echo "✅ Authenticated as: $ACTIVE_USER (Subscription: $ACTIVE_SUB)"

# 3. Register Azure Resource Providers
echo "⚙️ Ensuring Azure resource providers are registered..."
az provider register -n Microsoft.App --wait
az provider register -n Microsoft.OperationalInsights --wait
az provider register -n Microsoft.ContainerRegistry --wait

# 4. Install Container Apps CLI Extension
echo "🧩 Ensuring Azure Container Apps extension is installed..."
az extension add --name containerapp --upgrade --yes

# 5. Create or reuse Resource Group
echo "📁 Creating Resource Group '$RESOURCE_GROUP' in '$LOCATION'..."
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" -o none

# 6. Create or reuse Container App Environment
echo "🌐 Creating Container App Environment '$ENVIRONMENT_NAME'..."
az containerapp env create \
  --name "$ENVIRONMENT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  -o none

# 7. Create Azure Container Registry (ACR)
echo "📦 Creating Azure Container Registry '$REGISTRY_NAME'..."
az acr create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$REGISTRY_NAME" \
  --sku Basic \
  --admin-enabled true \
  -o none

ACR_SERVER=$(az acr show --name "$REGISTRY_NAME" --resource-group "$RESOURCE_GROUP" --query "loginServer" -o tsv)
ACR_USERNAME=$(az acr credential show --name "$REGISTRY_NAME" --resource-group "$RESOURCE_GROUP" --query "username" -o tsv)
ACR_PASSWORD=$(az acr credential show --name "$REGISTRY_NAME" --resource-group "$RESOURCE_GROUP" --query "passwords[0].value" -o tsv)

# 8. Build image in Azure ACR Tasks
echo "☁️ Building WACRM container image in Azure cloud (ACR Build)..."
az acr build \
  --registry "$REGISTRY_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --image "$APP_NAME:latest" \
  .

# 9. Read Secrets from .env.local
ENV_FILE=".env.local"
if [ ! -f "$ENV_FILE" ]; then
  ENV_FILE=".env.local.example"
fi

get_env() {
  grep "^$1=" "$ENV_FILE" | head -n 1 | cut -d '=' -f2- | tr -d '\r' | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//"
}

SUPA_URL=$(get_env "NEXT_PUBLIC_SUPABASE_URL")
SUPA_ANON=$(get_env "NEXT_PUBLIC_SUPABASE_ANON_KEY")
SUPA_SERVICE_ROLE=$(get_env "SUPABASE_SERVICE_ROLE_KEY")
ENC_KEY=$(get_env "ENCRYPTION_KEY")
META_SECRET=$(get_env "META_APP_SECRET")
META_APP_ID=$(get_env "META_APP_ID")
CRON_SECRET=$(get_env "AUTOMATION_CRON_SECRET")

# 10. Deploy Azure Container App
echo "🚀 Deploying to Azure Container Apps..."
az containerapp create \
  --name "$APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --environment "$ENVIRONMENT_NAME" \
  --image "$ACR_SERVER/$APP_NAME:latest" \
  --target-port 3000 \
  --ingress external \
  --min-replicas 0 \
  --max-replicas 2 \
  --registry-server "$ACR_SERVER" \
  --registry-username "$ACR_USERNAME" \
  --registry-password "$ACR_PASSWORD" \
  --secrets \
    "supabase-service-role=$SUPA_SERVICE_ROLE" \
    "encryption-key=$ENC_KEY" \
    "meta-secret=$META_SECRET" \
  --env-vars \
    "NEXT_PUBLIC_SUPABASE_URL=$SUPA_URL" \
    "NEXT_PUBLIC_SUPABASE_ANON_KEY=$SUPA_ANON" \
    "SUPABASE_SERVICE_ROLE_KEY=secretref:supabase-service-role" \
    "ENCRYPTION_KEY=secretref:encryption-key" \
    "META_APP_SECRET=secretref:meta-secret" \
    "META_APP_ID=$META_APP_ID" \
    "AUTOMATION_CRON_SECRET=$CRON_SECRET" \
    "PORT=3000" \
    "HOSTNAME=0.0.0.0" \
    "NODE_ENV=production" \
  -o none

# 11. Retrieve Public HTTPS URL
FQDN=$(az containerapp show --name "$APP_NAME" --resource-group "$RESOURCE_GROUP" --query "properties.configuration.ingress.fqdn" -o tsv)
APP_URL="https://$FQDN"

# 12. Update canonical site URL
az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --set-env-vars "NEXT_PUBLIC_SITE_URL=$APP_URL" \
  -o none

echo ""
echo "============================================================"
echo "🎉 Deployment Complete!"
echo "============================================================"
echo "🔗 Public Application URL: $APP_URL"
echo "🩺 Health Check Endpoint:  $APP_URL/api/health"
echo "📱 WhatsApp Webhook URL:   $APP_URL/api/whatsapp/webhook"
echo "============================================================"
