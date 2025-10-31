param(
  [Parameter(Mandatory=$true)][string]$ProxmoxHost,
  [int]$ProxmoxPort = 22,
  [string]$ProxmoxUser = "root",
  [string]$ProxmoxIdentityFile,

  [int]$CTID = 102,
  [string]$Hostname = "laundryapp",
  [string]$Storage = "local-lvm",
  [int]$DiskGB = 8,
  [int]$Cores = 2,
  [int]$MemoryMB = 2048,
  [int]$SwapMB = 512,
  [string]$Bridge = "vmbr0",

  [switch]$StaticIP,
  [string]$IPAddr,     # e.g. 192.168.50.74/24
  [string]$Gateway,    # e.g. 192.168.50.1

  [string]$CTPublicKeyPath, # Public key to inject into CT for root
  [string]$CTIdentityFile,  # Private key to reach the CT for deploy
  [int]$CTSSHPort = 22,

  [switch]$NoExternalHealth,
  # Default to repo root
  [string]$ProjectPath = (Resolve-Path (Join-Path $PSScriptRoot ".." )).Path
)

function Step($m){ Write-Host "==> $m" -ForegroundColor Cyan }
function Info($m){ Write-Host "    $m" -ForegroundColor Gray }
function Die($m){ Write-Error $m; exit 1 }

# Validate inputs
if ($StaticIP) {
  if (-not $IPAddr -or -not $Gateway) { Die "When -StaticIP is set, -IPAddr and -Gateway are required." }
}
if ($CTPublicKeyPath -and -not (Test-Path $CTPublicKeyPath)) { Die "CTPublicKeyPath not found: $CTPublicKeyPath" }

# Build base ssh/scp options to Proxmox host
$sshHost = "$ProxmoxUser@$ProxmoxHost"
$sshOpts = @()
$scpOpts = @()
if ($ProxmoxIdentityFile) { $sshOpts += @('-i',$ProxmoxIdentityFile); $scpOpts += @('-i',$ProxmoxIdentityFile) }
if ($ProxmoxPort -ne 22) { $sshOpts += @('-p',$ProxmoxPort.ToString()); $scpOpts += @('-P',$ProxmoxPort.ToString()) }

# Optionally upload CT public key to Proxmox host for pct create
$remotePubPath = $null
if ($CTPublicKeyPath) {
  $remotePubPath = "/root/${Hostname}.pub"
  Step "Uploading CT public key to Proxmox host ($remotePubPath)"
  & scp $scpOpts $CTPublicKeyPath "${sshHost}:$remotePubPath" | Out-Null
}

# Compose pct create command on Proxmox host
$netArg = if ($StaticIP) { "ip=${IPAddr},gw=${Gateway}" } else { 'ip=dhcp' }
$template = 'ubuntu-24.04-standard_24.04-1_amd64.tar.zst'
$pubkeyArg = if ($remotePubPath) { "-ssh-public-keys $remotePubPath" } else { '' }

$bootstrap = @(
  'set -e',
  'pveam update',
  "pveam download local '$template' || true",
  (
    'pct create {0} local:vztmpl/{1} -hostname {2} -rootfs {3}:{4} -cores {5} -memory {6} -swap {7} -net0 name=eth0,bridge={8},{9} -features nesting=1,keyctl=1 -unprivileged 0 {10}' -f 
      $CTID,$template,$Hostname,$Storage,$DiskGB,$Cores,$MemoryMB,$SwapMB,$Bridge,$netArg,$pubkeyArg
  ).Trim(),
  ('pct start {0}' -f $CTID),
  # Install Docker and tools inside CT
  ('pct exec {0} -- bash -lc ''apt-get update -y && apt-get install -y docker.io docker-compose-plugin ca-certificates unzip curl && systemctl enable --now docker''' -f $CTID),
  # Print first IP address
  ('pct exec {0} -- bash -lc ''hostname -I | cut -d" " -f1''' -f $CTID)
) -join ' && '

Step "Provisioning LXC CT $CTID on Proxmox host $ProxmoxHost"
Info ("ssh " + (($sshOpts + @($sshHost,'<bootstrap-cmd>')) -join ' '))
$ctIp = & ssh $sshOpts $sshHost $bootstrap | Select-Object -Last 1
if (-not $ctIp -or "$ctIp".Trim() -eq "") { Die "Failed to retrieve CT IP. Check Proxmox and network settings." }
Step "CT started with IP: $ctIp"

# Deploy to CT using existing deploy.ps1
$deploy = Join-Path $PSScriptRoot 'deploy.ps1'
if (-not (Test-Path $deploy)) { Die "deploy.ps1 not found at $deploy" }

$deployArgs = @('-TargetHost', $ctIp, '-ProjectPath', $ProjectPath)
if ($CTIdentityFile) { $deployArgs += @('-IdentityFile', $CTIdentityFile) }
if ($NoExternalHealth) { $deployArgs += '-NoExternalHealth' }

Step "Running deploy.ps1 to provision app inside CT ($ctIp)"
& $deploy $deployArgs

Step "All done. Visit: http://$ctIp:5000/"
