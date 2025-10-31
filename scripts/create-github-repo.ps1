param(
  [Parameter(Mandatory=$true)][string]$RepoName,
  [ValidateSet('private','public')][string]$Visibility = 'private',
  [string]$Description = 'LaundryApp containerized deployment',
  [string]$Owner, # default: authenticated user
  [switch]$SkipPush,
  [string]$GitName,
  [string]$GitEmail
)

function Step($m){ Write-Host "==> $m" -ForegroundColor Cyan }
function Info($m){ Write-Host "    $m" -ForegroundColor Gray }
function Die($m){ Write-Error $m; exit 1 }

# Preconditions
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $root

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  Die "Git is not installed. Install Git for Windows, restart PowerShell, and retry."
}

# Initialize git repo if needed
if (-not (Test-Path (Join-Path $root '.git'))) {
  Step "Initializing git repository"
  git init . | Out-Null
}

# Ensure .gitignore exists
$gi = Join-Path $root '.gitignore'
if (-not (Test-Path $gi)) {
  Step "Creating .gitignore"
  @(
    '# Node / React',
    'node_modules/',
    'frontend/node_modules/',
    'backend/node_modules/',
    'frontend/build/',
    'frontend/public/*.map',
    '',
    '# Logs & coverage',
    'logs/',
    'npm-debug.log*',
    'yarn-debug.log*',
    'yarn-error.log*',
    'coverage/',
    '',
    '# OS/editor',
    '.DS_Store',
    'Thumbs.db',
    '.vscode/',
    '',
    '# Env & misc',
    '.env',
    '*.zip',
    'scripts/logs/',
    '',
    '# Docker',
    '.docker/',
    'docker-data/'
  ) | Set-Content -NoNewline:$false -Encoding UTF8 $gi
}

# Ensure git identity (repo-local) if missing and provided
$currentName = git config user.name 2>$null
$currentEmail = git config user.email 2>$null
if (-not $currentName -and $GitName) { git config user.name "$GitName" }
if (-not $currentEmail -and $GitEmail) { git config user.email "$GitEmail" }

# First commit if nothing committed yet
$null = git rev-parse --verify HEAD 2>$null
$hasCommit = ($LASTEXITCODE -eq 0)
if (-not $hasCommit) {
  Step "Creating initial commit"
  git add .
  git commit -m "Initial commit: LaundryApp scaffolding" | Out-Null
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
  Die "GitHub CLI (gh) is not installed. Install from https://github.com/cli/cli/releases, or via winget: winget install --id GitHub.cli -e"
}

# Ensure authenticated to GitHub
& gh auth status 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
  Step "Logging into GitHub CLI (browser flow)"
  & gh auth login -s repo -w
  if ($LASTEXITCODE -ne 0) { Die "GitHub CLI auth failed. Please rerun after successful login." }
}

$remote = 'origin'
$visFlag = if ($Visibility -eq 'public') { '--public' } else { '--private' }
$ownerPrefix = if ($Owner) { "$Owner/" } else { '' }
$fullName = "$ownerPrefix$RepoName"

# Create the repo (if it doesn't already exist)
Step "Creating GitHub repo $fullName ($Visibility)"
& gh repo view $fullName 2>$null 1>$null
if ($LASTEXITCODE -ne 0) {
  & gh repo create $fullName $visFlag --source . --remote $remote --push
  if ($LASTEXITCODE -ne 0) { Die "Failed to create and push to GitHub repo $fullName" }
} else {
  Step "Repo exists; setting remote '$remote' and pushing"
  git remote remove $remote 2>$null | Out-Null
  git remote add $remote "https://github.com/$fullName.git"
  if (-not $SkipPush) { git push -u $remote HEAD:main 2>$null; if ($LASTEXITCODE -ne 0) { git push -u $remote HEAD:master } }
}

Step "Done"
Info "Repo: https://github.com/$fullName"
Info "Clone: git clone https://github.com/$fullName.git"
