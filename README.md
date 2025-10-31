# Laundry App Analytics

Dockerized laundry analytics app with React frontend and Node.js backend.

## Quick Start (Docker)

```bash
docker-compose up -d
```

Access: 
- HTTP: http://localhost:8090/ (or http://your-ip:8090/)
- HTTPS: https://laundry.adamdinjian.com:8453/ (with domain configured)

Internal app health (direct): http://localhost:5000/health (if exposed)

## HTTPS Setup

The included Caddy reverse proxy provides automatic HTTPS with Let's Encrypt.

### Prerequisites
1. Domain pointing to your server (e.g., `laundry.adamdinjian.com` A record → your public IP)
2. Ports forwarded on router: 8090 → host:8090, 8453 → host:8453
3. Update `Caddyfile` with your domain

### Configuration

Edit `Caddyfile`:
```
laundry.yourdomain.com {
    reverse_proxy app:5000
}
```

Then:
```bash
docker-compose up -d
```

Caddy automatically obtains and renews SSL certificates.

## Development

### Backend
```bash
cd backend
npm install
node server.js
```

### Frontend
```bash
cd frontend
npm install
npm start
```

## Deployment

The app is automatically built and pushed to GitHub Container Registry on every push to master.

### Pull and run from GHCR

```bash
docker-compose pull
docker-compose up -d
```

### Environment Variables

- `EXTERNAL_HEALTHCHECK` - Enable external health checks (default: true)
- `NODE_ENV` - production or development

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
