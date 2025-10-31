param(
  [Parameter(Mandatory=$true)][string]$TargetHost,
  [string]$User = "root",
  [int]$Port = 22,
  # Default to repo root (parent of this scripts directory)
  [string]$ProjectPath = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
  [string]$RemotePath = "/root",
  [string]$ZipPath,
  [switch]$NoExternalHealth,
  [string]$IdentityFile
)

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Info($msg) { Write-Host "    $msg" -ForegroundColor Gray }

# Resolve project name and default archive path
$ProjectFullPath = (Resolve-Path $ProjectPath).Path
$ProjectName = Split-Path -Leaf $ProjectFullPath
if (-not $ZipPath) {
  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
  # Prefer tar.gz by default to avoid Windows backslashes in zip entries
  $ArchivePath = Join-Path $env:TEMP ("$ProjectName-$timestamp.tar.gz")
} else {
  $ArchivePath = $ZipPath
}

$ext = [System.IO.Path]::GetExtension($ArchivePath)
$isTarGz = $ArchivePath.ToLower().EndsWith('.tar.gz')

Write-Step ("Creating archive: " + $ArchivePath)
if (Test-Path $ArchivePath) { Remove-Item -Force $ArchivePath }
# Archive the folder by running from the parent directory to keep a clean top-level folder
$parentDir = Split-Path -Parent $ProjectFullPath
$folderName = Split-Path -Leaf $ProjectFullPath
Push-Location $parentDir
try {
  if ($isTarGz) {
    # Use built-in bsdtar on Windows
    tar -czf $ArchivePath $folderName
  } else {
    # Fallback to zip
    Compress-Archive -Path $folderName -DestinationPath $ArchivePath -Force
  }
}
finally {
  Pop-Location
}

# Build scp/ssh options
$ScpOpts = @()
$SshOpts = @()
if ($IdentityFile) { $ScpOpts += @('-i', $IdentityFile); $SshOpts += @('-i', $IdentityFile) }
if ($Port -ne 22)     { $ScpOpts += @('-P', $Port.ToString()); $SshOpts += @('-p', $Port.ToString()) }
# Reduce first-connection prompts and timeouts
$ScpOpts += @('-o','StrictHostKeyChecking=no')
$SshOpts += @('-o','StrictHostKeyChecking=no','-o','ConnectTimeout=10')

# Preflight: ensure SSH port is reachable from this machine
try {
  $tnc = Test-NetConnection -ComputerName $TargetHost -Port $Port -WarningAction SilentlyContinue
} catch { $tnc = $null }
if (-not $tnc -or -not $tnc.TcpTestSucceeded) {
  Write-Host "ERROR: Cannot reach ${TargetHost}:$Port (SSH). Ensure the CT is up, SSH is running and listening on 0.0.0.0:$Port, and any firewalls allow inbound." -ForegroundColor Red
  Write-Host "Tip: From Windows run: Test-NetConnection -ComputerName $TargetHost -Port $Port" -ForegroundColor Yellow
  exit 1
}

# Upload zip
Write-Step "Uploading to $User@${TargetHost}:$RemotePath/"
$scpBase = @("$ArchivePath", "$User@${TargetHost}:$RemotePath/")
# Attempt modern scp (SFTP-based). If it fails, retry once with legacy -O.
$scpArgs1 = $ScpOpts + $scpBase
Write-Info ("scp " + ($scpArgs1 -join ' '))
& scp $scpArgs1
if (-not $?) {
  Write-Host "WARN: Upload failed with SFTP-based scp. Retrying once with legacy protocol (-O)..." -ForegroundColor Yellow
  $scpArgs2 = $ScpOpts + @('-O') + $scpBase
  Write-Info ("scp " + ($scpArgs2 -join ' '))
  & scp $scpArgs2
  if (-not $?) {
    Write-Host "ERROR: Upload failed (scp) with both SFTP and legacy modes. Ensure SSH is reachable, password or key auth works, and on the CT that either the SFTP subsystem is enabled (Subsystem sftp /usr/lib/openssh/sftp-server) or legacy scp is supported." -ForegroundColor Red
    exit 1
  }
}

# Remote commands: extract, cd, start
$remoteProjectDir = "$RemotePath/$ProjectName"
$remoteArchive = "$RemotePath/" + (Split-Path -Leaf $ArchivePath)
$extHealth = if ($NoExternalHealth) { 'false' } else { 'true' }
$remoteCmd = @(
  "set -e",
  # Ensure Docker is available (install if missing). On Ubuntu 20.04, docker-compose-plugin may not exist; fall back to docker-compose.
  "command -v docker >/dev/null 2>&1 || (apt-get update -y && apt-get install -y docker.io ca-certificates >/dev/null 2>&1 && (apt-get install -y docker-compose-plugin >/dev/null 2>&1 || apt-get install -y docker-compose >/dev/null 2>&1 || true) && (systemctl enable --now docker 2>/dev/null || service docker start 2>/dev/null || true))",
  "apt-get update -y >/dev/null 2>&1 || true",
  "apt-get install -y unzip tar >/dev/null 2>&1 || true",
  # Fail clearly if the archive isn't present
  "[ -f '$remoteArchive' ] || (echo 'ERROR: Expected upload $remoteArchive not found' >&2; exit 1)",
  # Extract depending on type
  (if ($isTarGz) { "tar -xzf '$remoteArchive' -C '$RemotePath'" } else { "unzip -o '$remoteArchive' -d '$RemotePath' >/dev/null" }),
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
    'docker --version || true',
    '(docker compose version || docker-compose --version) || true',
    '(docker ps -a || true) && echo --- && ((docker compose ps) || (docker-compose ps) || true)',
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
