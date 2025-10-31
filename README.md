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
