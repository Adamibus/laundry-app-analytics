param(
  [Parameter(Mandatory=$true)][string]$TargetHost,
  [string]$User = "root",
  [int]$Port = 22,
  # Used only to derive project name for default zip search
  [string]$ProjectPath = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
  [string]$RemotePath = "/root",
  [string]$ZipPath,
  [switch]$NoExternalHealth,
  [string]$IdentityFile
)

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Info($msg) { Write-Host "    $msg" -ForegroundColor Gray }
function Die($msg) { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }

# Derive project name and locate latest zip if not provided
$ProjectFullPath = (Resolve-Path $ProjectPath).Path
$ProjectName = Split-Path -Leaf $ProjectFullPath
if (-not $ZipPath) {
  $pattern = "$ProjectName-*.zip"
  $cand = Get-ChildItem -Path $env:TEMP -Filter $pattern -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $cand) {
    # fallback: any recent zip in TEMP
    $cand = Get-ChildItem -Path $env:TEMP -Filter *.zip -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  }
  if (-not $cand) { Die "No zip found in TEMP. Provide -ZipPath explicitly or run deploy.ps1 once to create one." }
  $ZipPath = $cand.FullName
}
if (-not (Test-Path $ZipPath)) { Die "Zip not found: $ZipPath" }

Write-Step "Using zip: $ZipPath"

# Build scp/ssh options
$ScpOpts = @()
$SshOpts = @()
if ($IdentityFile) { $ScpOpts += @('-i', $IdentityFile); $SshOpts += @('-i', $IdentityFile) }
if ($Port -ne 22)     { $ScpOpts += @('-P', $Port.ToString()); $SshOpts += @('-p', $Port.ToString()) }
# Reduce first-connection prompts and timeouts; prefer legacy scp protocol
$ScpOpts += @('-o','StrictHostKeyChecking=no')
$ScpOpts += @('-O')
$SshOpts += @('-o','StrictHostKeyChecking=no','-o','ConnectTimeout=10')

# Preflight: ensure SSH port is reachable from this machine
try {
  $tnc = Test-NetConnection -ComputerName $TargetHost -Port $Port -WarningAction SilentlyContinue
} catch { $tnc = $null }
if (-not $tnc -or -not $tnc.TcpTestSucceeded) {
  Die "Cannot reach ${TargetHost}:$Port (SSH). Ensure the CT is up, SSH is running and listening on 0.0.0.0:$Port, and any firewalls allow inbound."
}

# Upload zip
Write-Step "Uploading to $User@${TargetHost}:$RemotePath/"
$scpArgs = $ScpOpts + @("$ZipPath", "$User@${TargetHost}:$RemotePath/")
Write-Info ("scp " + ($scpArgs -join ' '))
& scp $scpArgs
if (-not $?) { Die "Upload failed (scp). If you were prompted for a password and then saw 'Connection reset', ensure SFTP is enabled or retry with -IdentityFile." }

# Remote deploy sequence
$remoteProjectDir = "$RemotePath/$ProjectName"
$remoteZip = "$RemotePath/" + (Split-Path -Leaf $ZipPath)
$extHealth = if ($NoExternalHealth) { 'false' } else { 'true' }
$remoteCmd = @(
  "set -e",
  # Ensure Docker is available (install if missing). On Ubuntu 20.04, docker-compose-plugin may not exist; fall back to docker-compose.
  "command -v docker >/dev/null 2>&1 || (apt-get update -y && apt-get install -y docker.io ca-certificates >/dev/null 2>&1 && (apt-get install -y docker-compose-plugin >/dev/null 2>&1 || apt-get install -y docker-compose >/dev/null 2>&1 || true) && (systemctl enable --now docker 2>/dev/null || service docker start 2>/dev/null || true))",
  "apt-get update -y >/dev/null 2>&1 || true",
  "apt-get install -y unzip >/dev/null 2>&1 || true",
  "[ -f '$remoteZip' ] || (echo 'ERROR: Expected upload $remoteZip not found' >&2; exit 1)",
  "unzip -o '$remoteZip' -d '$RemotePath' >/dev/null",
  "cd '$remoteProjectDir'",
  "EXTERNAL_HEALTHCHECK=$extHealth ./scripts/start.sh"
) -join ' && '

Write-Step "Deploying on remote host"
$sshArgs = $SshOpts + @("$User@${TargetHost}", $remoteCmd)
Write-Info ("ssh " + ($sshArgs -join ' '))
& ssh $sshArgs
if ($LASTEXITCODE -ne 0) {
  Write-Host "ERROR: Remote deploy step failed (non-zero exit code). Gathering quick diagnostics..." -ForegroundColor Red
  $diag = @(
    'set -e',
    "cd '$remoteProjectDir' 2>/dev/null || true",
    # Show docker/compose availability and service state
    'docker --version || true',
    '(docker compose version || docker-compose --version) || true',
    # Show containers and compose status
    '(docker ps -a || true) && echo --- && ((docker compose ps) || (docker-compose ps) || true)',
    # If container exists, show last 200 log lines
    "(docker ps -a --format '{{.Names}}' | grep -x 'laundry-app' >/dev/null 2>&1 && docker logs --tail 200 laundry-app) || true"
  ) -join ' && '
  & ssh $SshOpts "$User@${TargetHost}" $diag
  exit 1
}

Write-Step "Deployment triggered. Checking status..."
$checkCmd = "docker ps --filter name=laundry-app && echo --- && curl -fsS http://localhost:5000/health || true"
$sshArgs2 = $SshOpts + @("$User@${TargetHost}", $checkCmd)
& ssh $sshArgs2

Write-Step "Done. Visit http://${TargetHost}:5000/"
