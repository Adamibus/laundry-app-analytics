#!/bin/bash
# Restore laundry log data from a backup
# Usage: ./restore-backup.sh [backup_file]

set -e

BACKUP_DIR="/root/LaundryApp/backups"

if [ -z "$1" ]; then
    echo "Available backups:"
    echo "================="
    ls -lht "$BACKUP_DIR"/laundry_log_*.jsonl 2>/dev/null || echo "No backups found"
    echo ""
    echo "Usage: $0 <backup_file>"
    echo "Example: $0 laundry_log_20251031_143000.jsonl"
    exit 1
fi

BACKUP_FILE="$1"

# Check if it's just a filename or full path
if [[ "$BACKUP_FILE" != /* ]]; then
    BACKUP_FILE="$BACKUP_DIR/$BACKUP_FILE"
fi

if [ ! -f "$BACKUP_FILE" ]; then
    echo "Error: Backup file not found: $BACKUP_FILE"
    exit 1
fi

echo "Restoring from: $BACKUP_FILE"
echo ""
read -p "This will replace current log data. Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled"
    exit 0
fi

# Create a backup of current data before restoring
if docker exec laundry-app test -f /app/backend/laundry_log.jsonl 2>/dev/null; then
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    docker cp laundry-app:/app/backend/laundry_log.jsonl "$BACKUP_DIR/laundry_log_before_restore_$TIMESTAMP.jsonl"
    echo "Current data backed up to: laundry_log_before_restore_$TIMESTAMP.jsonl"
fi

# Restore the backup
docker cp "$BACKUP_FILE" laundry-app:/app/backend/laundry_log.jsonl

echo ""
echo "Restore complete!"
echo ""

# Show some stats
LINES=$(docker exec laundry-app wc -l /app/backend/laundry_log.jsonl | awk '{print $1}')
echo "Restored log contains $LINES entries"
