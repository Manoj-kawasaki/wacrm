<#
.SYNOPSIS
  Automated deployment of WACRM to Azure Container Apps (ACA).
.DESCRIPTION
  Deploys the standalone Next.js WACRM container to Azure Container Apps with:
  - Resource Group: cloudzap-wacrm-rg
  - Region: centralindia
  - Environment: cloudzap-wacrm-env
  - Container App: wacrm
  - Target Port: 3000
  - Ingress: external (HTTPS)
  - Scale: min 0, max 2
  - Secrets injected securely
#>

param(
  [string]$ResourceGroup = "cloudzap-wacrm-rg",
  [string]$Location = "centralindia",
  [string]$EnvironmentName = "cloudzap-wacrm-env",
  [string]$AppName = "wacrm",
  [string]$RegistryName = "cloudzapwacrm$((Get-Random -Minimum 1000 -Maximum 9999))"
)

$ErrorActionPreference = "Stop"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "🚀 Deploying WACRM to Azure Container Apps" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "📦 Resource Group:  $ResourceGroup"
Write-Host "📍 Azure Region:    $Location"
Write-Host "🌐 Environment:     $EnvironmentName"
Write-Host "🛠 Container App:   $AppName"
Write-Host "⚓ Target Port:     3000"
Write-Host "⚖️ Replicas:        Min 0 (scale-to-zero) / Max 2"
Write-Host ""

# 1. Verify Azure CLI is installed
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
  # Check standard path
  if (Test-Path "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd") {
    $env:PATH = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin;$env:PATH"
  } else {
    Write-Host "❌ Error: Azure CLI ('az') is not installed or not in PATH." -ForegroundColor Red
    Write-Host "Please install Azure CLI or restart PowerShell after install." -ForegroundColor Yellow
    exit 1
  }
}

# 2. Verify Authentication
Write-Host "🔐 Verifying Azure CLI authentication..." -ForegroundColor Yellow
$account = az account show --query "{name:name, id:id, user:user.name}" -o json 2>$null | ConvertFrom-Json
if (-not $account) {
  Write-Host "⚠️ Not logged in to Azure. Launching 'az login'..." -ForegroundColor Yellow
  az login
  $account = az account show --query "{name:name, id:id, user:user.name}" -o json | ConvertFrom-Json
}
Write-Host "✅ Authenticated as: $($account.user) (Subscription: $($account.name))" -ForegroundColor Green

# 3. Register Azure Resource Providers
Write-Host "⚙️ Ensuring Azure resource providers are registered..." -ForegroundColor Yellow
az provider register -n Microsoft.App --wait
az provider register -n Microsoft.OperationalInsights --wait
az provider register -n Microsoft.ContainerRegistry --wait

# 4. Install Container Apps CLI Extension
Write-Host "🧩 Ensuring Azure Container Apps CLI extension is installed..." -ForegroundColor Yellow
az extension add --name containerapp --upgrade --yes

# 5. Create or reuse Resource Group
Write-Host "📁 Creating Resource Group '$ResourceGroup' in '$Location'..." -ForegroundColor Yellow
az group create --name $ResourceGroup --location $Location -o none

# 6. Create or reuse Container App Environment
Write-Host "🌐 Creating Container App Environment '$EnvironmentName'..." -ForegroundColor Yellow
az containerapp env create `
  --name $EnvironmentName `
  --resource-group $ResourceGroup `
  --location $Location `
  -o none

# 7. Create Azure Container Registry (ACR) to build and host the image
Write-Host "📦 Creating Azure Container Registry '$RegistryName'..." -ForegroundColor Yellow
az acr create `
  --resource-group $ResourceGroup `
  --name $RegistryName `
  --sku Basic `
  --admin-enabled true `
  -o none

$acrServer = az acr show --name $RegistryName --resource-group $ResourceGroup --query "loginServer" -o tsv
$acrCredentials = az acr credential show --name $RegistryName --resource-group $ResourceGroup | ConvertFrom-Json
$acrUsername = $acrCredentials.username
$acrPassword = $acrCredentials.passwords[0].value

# 8. Build image using Azure ACR Cloud Tasks (no local Docker required)
Write-Host "☁️ Building WACRM container image in Azure cloud (ACR Build)..." -ForegroundColor Yellow
az acr build `
  --registry $RegistryName `
  --resource-group $ResourceGroup `
  --image "$($AppName):latest" `
  .

# 9. Read Secrets from .env.local
$envFile = ".env.local"
if (-not (Test-Path $envFile)) {
  $envFile = ".env.local.example"
}

$envMap = @{}
Get-Content $envFile | ForEach-Object {
  $line = $_.Trim()
  if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
    $idx = $line.IndexOf("=")
    $k = $line.Substring(0, $idx).Trim()
    $v = $line.Substring($idx + 1).Trim().Trim('"').Trim("'")
    $envMap[$k] = $v
  }
}

$supaUrl = $envMap["NEXT_PUBLIC_SUPABASE_URL"]
$supaAnon = $envMap["NEXT_PUBLIC_SUPABASE_ANON_KEY"]
$supaServiceRole = $envMap["SUPABASE_SERVICE_ROLE_KEY"]
$encKey = $envMap["ENCRYPTION_KEY"]
$metaSecret = $envMap["META_APP_SECRET"]
$metaAppId = $envMap["META_APP_ID"]
$cronSecret = $envMap["AUTOMATION_CRON_SECRET"]

# 10. Deploy or update Azure Container App
Write-Host "🚀 Deploying to Azure Container Apps..." -ForegroundColor Yellow
az containerapp create `
  --name $AppName `
  --resource-group $ResourceGroup `
  --environment $EnvironmentName `
  --image "$acrServer/$($AppName):latest" `
  --target-port 3000 `
  --ingress external `
  --min-replicas 0 `
  --max-replicas 2 `
  --registry-server $acrServer `
  --registry-username $acrUsername `
  --registry-password $acrPassword `
  --secrets `
    "supabase-service-role=$supaServiceRole" `
    "encryption-key=$encKey" `
    "meta-secret=$metaSecret" `
  --env-vars `
    "NEXT_PUBLIC_SUPABASE_URL=$supaUrl" `
    "NEXT_PUBLIC_SUPABASE_ANON_KEY=$supaAnon" `
    "SUPABASE_SERVICE_ROLE_KEY=secretref:supabase-service-role" `
    "ENCRYPTION_KEY=secretref:encryption-key" `
    "META_APP_SECRET=secretref:meta-secret" `
    "META_APP_ID=$metaAppId" `
    "AUTOMATION_CRON_SECRET=$cronSecret" `
    "PORT=3000" `
    "HOSTNAME=0.0.0.0" `
    "NODE_ENV=production" `
  -o none

# 11. Retrieve Public HTTPS URL
$fqdn = az containerapp show --name $AppName --resource-group $ResourceGroup --query "properties.configuration.ingress.fqdn" -o tsv
$appUrl = "https://$fqdn"

# 12. Update NEXT_PUBLIC_SITE_URL to canonical FQDN
az containerapp update `
  --name $AppName `
  --resource-group $ResourceGroup `
  --set-env-vars "NEXT_PUBLIC_SITE_URL=$appUrl" `
  -o none

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "🎉 Deployment Complete!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host "🔗 Public Application URL: $appUrl" -ForegroundColor Cyan
Write-Host "🩺 Health Check Endpoint:  $appUrl/api/health" -ForegroundColor Cyan
Write-Host "📱 WhatsApp Webhook URL:   $appUrl/api/whatsapp/webhook" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Green
