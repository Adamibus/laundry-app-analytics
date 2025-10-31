# Laundry App Analytics

Dockerized laundry analytics app with React frontend and Node.js backend.

## Quick Start (Docker)

```bash
docker-compose up -d
```

Access: http://localhost:5000/

Health: http://localhost:5000/health

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
