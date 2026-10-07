<#
.SYNOPSIS
  Automated deployment of WACRM to Google Cloud Run for Windows PowerShell.
.EXAMPLE
  .\deploy-cloudrun.ps1 -ProjectId "my-gcp-project" -Region "asia-south1"
#>
param(
  [Parameter(Mandatory=$false)]
  [string]$ProjectId,

  [Parameter(Mandatory=$false)]
  [string]$Region = "asia-south1",

  [Parameter(Mandatory=$false)]
  [string]$ServiceName = "wacrm"
)

if (-not $ProjectId) {
  $ProjectId = (gcloud config get-value project 2>$null)
}

if (-not $ProjectId) {
  Write-Host "❌ Error: Google Cloud Project ID is required." -ForegroundColor Red
  Write-Host "Usage: .\deploy-cloudrun.ps1 -ProjectId '<YOUR_GCP_PROJECT_ID>' [-Region 'asia-south1']" -ForegroundColor Yellow
  exit 1
}

Write-Host "🚀 Deploying WACRM to Google Cloud Run..." -ForegroundColor Cyan
Write-Host "📦 Project ID: $ProjectId" -ForegroundColor Cyan
Write-Host "📍 Region:     $Region" -ForegroundColor Cyan
Write-Host "🛠 Service:    $ServiceName" -ForegroundColor Cyan

# Enable APIs
Write-Host "⚙️ Enabling Google Cloud Run & Cloud Build APIs..." -ForegroundColor Yellow
gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com --project $ProjectId

# Deploy using Cloud Build source deploy
Write-Host "☁️ Deploying container to Cloud Run (Cloud Build will compile Dockerfile)..." -ForegroundColor Yellow
gcloud run deploy $ServiceName `
  --source . `
  --project $ProjectId `
  --region $Region `
  --platform managed `
  --allow-unauthenticated `
  --port 8080 `
  --memory 1Gi `
  --cpu 1 `
  --min-instances 0 `
  --max-instances 5

Write-Host "✅ WACRM successfully deployed to Google Cloud Run!" -ForegroundColor Green
$serviceUrl = gcloud run services describe $ServiceName --project $ProjectId --region $Region --format="value(status.url)"
Write-Host "🔗 Live Service URL: $serviceUrl" -ForegroundColor Green
