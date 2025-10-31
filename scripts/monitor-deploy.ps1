param(
  [Parameter(Mandatory=$true)][string]$TargetHost,
  [string]$User = "root",
  [int]$Port = 22,
  [string]$IdentityFile,
  [switch]$NoExternalHealth,
  # Default to repo root (parent of this scripts directory)
  [string]$ProjectPath = (Resolve-Path (Join-Path $PSScriptRoot ".." )).Path
)

function Step($m){ Write-Host "==> $m" -ForegroundColor Cyan }
function Info($m){ Write-Host "    $m" -ForegroundColor Gray }
function Die($m){ Write-Error $m; exit 1 }

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logDir = Join-Path $PSScriptRoot 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$logPath = Join-Path $logDir ("deploy-$($TargetHost)-$timestamp.log")

Step "Checking SSH reachability to ${TargetHost}:$Port"
$tnc = $null
try { $tnc = Test-NetConnection -ComputerName $TargetHost -Port $Port -WarningAction SilentlyContinue } catch { $tnc = $null }
if (-not $tnc -or -not $tnc.TcpTestSucceeded) { Die "Cannot reach ${TargetHost}:$Port (SSH). Fix networking/ssh then retry." }

$deploy = Join-Path $PSScriptRoot 'deploy.ps1'
if (-not (Test-Path $deploy)) { Die "deploy.ps1 not found at $deploy" }

$splat = @{ TargetHost = $TargetHost; ProjectPath = $ProjectPath }
if ($IdentityFile) { $splat.IdentityFile = $IdentityFile }
if ($User -and $User -ne 'root') { $splat.User = $User }
if ($Port -ne 22) { $splat.Port = $Port }
if ($NoExternalHealth) { $splat.NoExternalHealth = $true }

Step "Starting deploy; streaming to $logPath"
# Use named-parameter splatting for robust forwarding
& $deploy @splat 2>&1 | Tee-Object -FilePath $logPath
$exitCode = $LASTEXITCODE
$ok = $?

Step "Deploy finished. ExitCode=$exitCode"

# Basic log scan for common issues
$patterns = @(
  'error', 'failed', 'permission denied', 'timed out', 'connection refused',
  'Cannot reach', 'Cannot GET', 'ECONNREFUSED', 'No such file or directory'
)
$hits = @()
if (Test-Path $logPath) {
  $text = Get-Content $logPath -Raw
  foreach ($p in $patterns) { if ($text -match $p) { $hits += $p } }
}

if ($hits.Count -gt 0 -or $exitCode -ne 0 -or -not $ok) {
  $unique = $hits | Sort-Object -Unique
  Write-Host ("==> Potential issues detected: " + ($unique -join ', ')) -ForegroundColor Yellow
  Write-Host "    See log: $logPath"
  exit 1
} else {
  Write-Host "==> Looks good. See log: $logPath" -ForegroundColor Green
  exit 0
}
