param(
  [string]$Endpoint = "https://cloud.appwrite.io/v1",
  [Parameter(Mandatory = $true)][string]$ProjectId
)

$ErrorActionPreference = "Stop"

Push-Location (Split-Path $PSScriptRoot -Parent)
try {
  flutter build web `
    --release `
    --dart-define=APPWRITE_ENDPOINT="$Endpoint" `
    --dart-define=APPWRITE_PROJECT_ID="$ProjectId"
  Write-Host "Built to teachers_help/build/web"
} finally {
  Pop-Location
}

