param(
  [string]$Endpoint = "https://cloud.appwrite.io/v1",
  [Parameter(Mandatory = $true)][string]$ProjectId
)

$ErrorActionPreference = "Stop"

Push-Location (Split-Path $PSScriptRoot -Parent)
try {
  flutter run -d chrome `
    --dart-define=APPWRITE_ENDPOINT="$Endpoint" `
    --dart-define=APPWRITE_PROJECT_ID="$ProjectId"
} finally {
  Pop-Location
}

