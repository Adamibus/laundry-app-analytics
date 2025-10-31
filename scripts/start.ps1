param(
  [switch]$NoExternalHealth
)

$env:EXTERNAL_HEALTHCHECK = if ($NoExternalHealth) { "false" } else { "true" }
Write-Host "Building and starting stack (EXTERNAL_HEALTHCHECK=$env:EXTERNAL_HEALTHCHECK)..."
docker compose up -d --build
Write-Host "Done. Status:"
docker ps --filter name=laundry-app
