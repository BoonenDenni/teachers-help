param(
  [Parameter(Mandatory = $true)][string]$ProjectId,
  [Parameter(Mandatory = $true)][string]$ApiKey,
  [string]$Endpoint = "https://cloud.appwrite.io/v1",
  [string]$DatabaseId = "teachers_help"
)

$ErrorActionPreference = "Stop"

function Require-Command($name) {
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
    throw "Missing required command: $name"
  }
}

Require-Command "appwrite"

$env:APPWRITE_ENDPOINT = $Endpoint
$env:APPWRITE_PROJECT_ID = $ProjectId
$env:APPWRITE_API_KEY = $ApiKey

Write-Host "Adding tabColorHex to collection tabs in database $DatabaseId (endpoint=$Endpoint)..."

appwrite databases create-string-attribute `
  --database-id $DatabaseId `
  --collection-id "tabs" `
  --key "tabColorHex" `
  --size 16 `
  --required false

Write-Host ""
Write-Host "Done. In Appwrite Console, wait until the attribute status is available (not building), then try changing the tab color again."
