# Laundry App Analytics

Dockerized laundry analytics app with React frontend and Node.js backend. Monitors laundry machine availability with automated scraping, logging, and analytics.

## Quick Start (Docker)

```bash
docker-compose up -d
```

Access: 
- HTTP: http://localhost:8090/ (or http://your-ip:8090/)
- HTTPS: https://your-domain.com:8453/ (with domain configured)

Internal app health (direct): http://localhost:5000/health (if exposed)

## Deployment Workflow

This project uses a CI/CD pipeline for automated builds and deployment to a Proxmox LXC container.

### Overview

1. **Development** → Push code to GitHub
2. **CI/CD** → GitHub Actions builds Docker image
3. **Registry** → Image pushed to GitHub Container Registry (GHCR)
4. **Production** → LXC container pulls and runs image

### Initial Setup

#### 1. GitHub Repository Setup

Created repository: [YourUsername/laundry-app-analytics](https://github.com/YourUsername/laundry-app-analytics)

```bash
# Initialize git and add remote
git init
git add .
git commit -m "Initial commit"
git branch -M master
git remote add origin git@github.com:YourUsername/laundry-app-analytics.git
git push -u origin master
```

#### 2. CI/CD Pipeline

GitHub Actions workflow (`.github/workflows/docker-image.yml`) automatically:
- Triggers on push to `master` branch
- Builds multi-stage Docker image (Node 20)
- Pushes to `ghcr.io/yourusername/laundry-app-analytics:latest`
- No manual authentication needed (uses `GITHUB_TOKEN`)

#### 3. Proxmox LXC Container Configuration

**Container Specs:**
- OS: Ubuntu 20.04
- CT ID: 102
- IP: 192.168.50.XXX
- Unprivileged: false (required for Docker)

**Required LXC Config** (edit on Proxmox host):
```bash
pct set 102 -features nesting=1,keyctl=1
```

Edit `/etc/pve/lxc/102.conf`:
```
lxc.apparmor.profile: unconfined
lxc.cgroup.devices.allow: a
```

Restart container: `pct stop 102 && pct start 102`

#### 4. LXC Container Setup

Install Docker in CT:
```bash
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
systemctl enable docker
systemctl start docker
```

Install Docker Compose v1 (Ubuntu 20.04):
```bash
apt-get install -y docker-compose
```

Configure SSH for GitHub (if using SSH):
```bash
ssh-keygen -t ed25519 -C "laundry-app-ct"
cat ~/.ssh/id_ed25519.pub  # Add to GitHub account
```

Configure Git identity:
```bash
git config --global user.name "YourUsername"
git config --global user.email "your-email@example.com"
```

Clone repository:
```bash
cd ~
git clone git@github.com:YourUsername/laundry-app-analytics.git LaundryApp
cd LaundryApp
```

#### 5. Initial Deployment

```bash
cd ~/LaundryApp
docker-compose pull  # Pull latest image from GHCR
docker-compose up -d
```

Verify deployment:
```bash
docker ps  # Check containers running
docker logs laundry-app  # Check app logs
curl http://localhost:8090/  # Test HTTP access
```

### Updating the App

#### Option 1: Automatic Deployment (Recommended)

Set up auto-deployment once on the CT to automatically pull and deploy updates every 5 minutes:

```bash
cd ~/LaundryApp
bash scripts/setup-auto-deploy.sh
```

This configures a cron job that:
- Checks for new commits every 5 minutes
- **Automatically backs up log data** before deployment
- Automatically pulls changes from GitHub
- Pulls the latest Docker image from GHCR
- Restarts containers with zero interaction needed
- **Restores log data** after restart (prevents data loss)
- Keeps last 10 backups in `/root/LaundryApp/backups/`

**View auto-deployment logs:**
```bash
tail -f /var/log/laundry-auto-deploy.log
```

**Manually trigger deployment:**
```bash
/root/LaundryApp/scripts/auto-deploy.sh
```

**List available backups:**
```bash
ls -lht /root/LaundryApp/backups/
```

**Restore from a backup:**
```bash
bash scripts/restore-backup.sh laundry_log_20251031_143000.jsonl
```

**Disable auto-deployment:**
```bash
crontab -e  # Remove the auto-deploy.sh line
```

#### Option 2: Manual Deployment

Whenever you push code changes to GitHub:

1. **GitHub Actions automatically builds and pushes** new image to GHCR

2. **On the LXC container**, pull and restart:
```bash
cd ~/LaundryApp
git pull origin master  # Update docker-compose.yml and configs
docker-compose pull     # Pull new image
docker-compose down
docker-compose up -d
```

3. **Verify update**:
```bash
docker logs laundry-app  # Check for startup messages
curl http://localhost:8090/health  # Test health endpoint
```

### Timezone Configuration

The app runs in **America/New_York** timezone (set via `TZ` environment variable in `docker-compose.yml`).

**If you need to clear old UTC-timestamped data:**
```bash
docker exec laundry-app rm /app/backend/laundry_log.jsonl
docker-compose restart
```

Wait 5-10 minutes for fresh data to be collected with correct timestamps.

### Environment Variables

Configured in `docker-compose.yml`:
- `TZ=America/New_York` - Timezone for timestamps
- `EXTERNAL_HEALTHCHECK=true` - Enable external health checks
- `NODE_ENV=production` - Production mode

## HTTPS Setup

The included Caddy reverse proxy provides automatic HTTPS with Let's Encrypt.

### Prerequisites
1. Domain pointing to your server (e.g., `your-domain.com` A record → your public IP)
2. Ports forwarded on router: 
   - External 80 → Your-LXC-IP:8090
   - External 443 → Your-LXC-IP:8453
3. `Caddyfile` configured with your domain

### Configuration

Update the `Caddyfile` with your domain:
```
your-domain.com {
    reverse_proxy app:5000
}
```

Caddy automatically obtains and renews SSL certificates from Let's Encrypt.

**Access:**
- Local: http://Your-LXC-IP:8090/
- External: https://your-domain.com/ (with port forwarding)

## Development

### Local Development (without Docker)

Backend:
```bash
cd backend
npm install
node server.js
```

Frontend:
```bash
cd frontend
npm install
npm start
```

### Testing Docker Build Locally

```bash
docker build -t laundry-app:test .
docker run -p 5000:5000 -e NODE_ENV=production laundry-app:test
```

## Architecture

- **Frontend**: React app served as static build
- **Backend**: Express server serving API and frontend
- **Container**: Multi-stage Docker build, single service deployment

## Scripts

- `scripts/start.sh` - Start with docker-compose
- `scripts/stop.sh` - Stop containers
- `scripts/restart.sh` - Restart stack
- `scripts/logs.sh` - View logs

## Security Hardening (Optional)

### 1. Add Security Headers to Caddy

Edit `Caddyfile` and add header block:
```
laundry.adamdinjian.com {
    reverse_proxy app:5000
    
    header {
        X-Frame-Options "SAMEORIGIN"
        X-Content-Type-Options "nosniff"
        X-XSS-Protection "1; mode=block"
        Referrer-Policy "strict-origin-when-cross-origin"
        Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline';"
        -Server
    }
}
```

### 2. Enable Firewall (on CT as root)

```bash
apt-get install -y ufw
ufw allow 8090/tcp comment 'HTTP for Caddy'
ufw allow 8453/tcp comment 'HTTPS for Caddy'
ufw allow 22/tcp comment 'SSH'
ufw enable
```

### 3. Install Fail2Ban (SSH protection)

```bash
apt-get install -y fail2ban
systemctl enable fail2ban
systemctl start fail2ban
```

### 4. Enable Automatic Security Updates

```bash
apt-get install -y unattended-upgrades
dpkg-reconfigure -plow unattended-upgrades
```

### 5. Disable SSH Password Auth (keys only)

Edit `/etc/ssh/sshd_config`:
```
PermitRootLogin prohibit-password
PasswordAuthentication no
```

Then: `systemctl restart sshd`

**Note:** Ensure SSH keys are configured before disabling password auth.
