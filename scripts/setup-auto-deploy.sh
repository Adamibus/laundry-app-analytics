#!/bin/bash
# Setup auto-deployment on CT
# Run this once on the CT to enable automatic deployments

set -e

echo "Setting up auto-deployment for Laundry App..."

# Create log directory if it doesn't exist
sudo mkdir -p /var/log
sudo touch /var/log/laundry-auto-deploy.log
sudo chmod 666 /var/log/laundry-auto-deploy.log

# Make auto-deploy script executable
chmod +x /root/LaundryApp/scripts/auto-deploy.sh

# Add cron job to check for updates every 5 minutes
CRON_JOB="*/5 * * * * /root/LaundryApp/scripts/auto-deploy.sh >> /var/log/laundry-auto-deploy.log 2>&1"

# Check if cron job already exists
if crontab -l 2>/dev/null | grep -q "auto-deploy.sh"; then
    echo "Cron job already exists"
else
    # Add cron job
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    echo "Cron job added: Check for updates every 5 minutes"
fi

echo ""
echo "Auto-deployment setup complete!"
echo ""
echo "The CT will now automatically:"
echo "  1. Check for new commits every 5 minutes"
echo "  2. Pull changes from GitHub"
echo "  3. Pull new Docker image from GHCR"
echo "  4. Restart containers"
echo ""
echo "View deployment logs with:"
echo "  tail -f /var/log/laundry-auto-deploy.log"
echo ""
echo "To manually trigger deployment:"
echo "  /root/LaundryApp/scripts/auto-deploy.sh"
echo ""
echo "To disable auto-deployment:"
echo "  crontab -e  (then remove the auto-deploy.sh line)"
