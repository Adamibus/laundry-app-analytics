#!/bin/bash
# Auto-deployment script for CT
# This script checks for updates from GitHub and deploys automatically

set -e

REPO_DIR="/root/LaundryApp"
LOG_FILE="/var/log/laundry-auto-deploy.log"
LOCK_FILE="/tmp/laundry-deploy.lock"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Check if already running
if [ -f "$LOCK_FILE" ]; then
    log "Deploy already in progress, exiting"
    exit 0
fi

# Create lock file
touch "$LOCK_FILE"
trap "rm -f $LOCK_FILE" EXIT

cd "$REPO_DIR"

# Fetch latest changes
git fetch origin master

# Check if we're behind
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/master)

if [ "$LOCAL" = "$REMOTE" ]; then
    log "Already up to date"
    exit 0
fi

log "New changes detected, deploying..."
log "Local: $LOCAL"
log "Remote: $REMOTE"

# Backup current log data before deployment
BACKUP_DIR="/root/LaundryApp/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
mkdir -p "$BACKUP_DIR"

log "Backing up laundry log data..."
if docker exec laundry-app test -f /app/backend/laundry_log.jsonl 2>/dev/null; then
    docker cp laundry-app:/app/backend/laundry_log.jsonl "$BACKUP_DIR/laundry_log_$TIMESTAMP.jsonl"
    log "Backup created: $BACKUP_DIR/laundry_log_$TIMESTAMP.jsonl"
    
    # Keep only last 10 backups
    cd "$BACKUP_DIR"
    ls -t laundry_log_*.jsonl | tail -n +11 | xargs -r rm
    log "Cleaned up old backups (keeping last 10)"
else
    log "No log data to backup"
fi

# Pull changes
git pull origin master

# Pull new Docker image
log "Pulling latest Docker image..."
docker-compose pull

# Restart containers
log "Restarting containers..."
docker-compose down
docker-compose up -d

# Restore log data if it exists in backup
log "Restoring log data..."
if [ -f "$BACKUP_DIR/laundry_log_$TIMESTAMP.jsonl" ]; then
    sleep 5  # Wait for container to be ready
    docker cp "$BACKUP_DIR/laundry_log_$TIMESTAMP.jsonl" laundry-app:/app/backend/laundry_log.jsonl
    log "Log data restored successfully"
else
    log "No backup to restore"
fi

# Wait for health check
log "Waiting for app to be healthy..."
sleep 10

# Check health
if curl -f http://localhost:5000/health > /dev/null 2>&1; then
    log "Deployment successful!"
else
    log "WARNING: Health check failed"
fi

log "Auto-deployment completed"
