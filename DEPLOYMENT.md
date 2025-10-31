---
# Conn College Laundry Analytics: Docker Deployment Guide (Ubuntu)

This guide will help you deploy both the backend and frontend in a single Docker container on Ubuntu (in a Proxmox CT).

---

## 1. Prerequisites
- Proxmox CT running Ubuntu (22.04 recommended)
- Docker and Docker Compose installed
- Your app code (both backend and frontend) in the CT

### Publish this project to GitHub (first time)

If your repo isn’t created yet and you want to deploy by pulling from GitHub, run this from Windows PowerShell in the project root:

```powershell
./scripts/create-github-repo.ps1 -RepoName <your-repo-name> -Visibility private
```

This script will:
- Initialize git (if needed), add a sensible `.gitignore`, and create the first commit
- Use GitHub CLI to create `https://github.com/<you>/<your-repo-name>` and push

Requirements: Git and GitHub CLI (gh). If `gh` isn’t installed, install via winget:

```powershell
winget install --id GitHub.cli -e
```

Once published, on the CT you can either `git clone https://github.com/<you>/<your-repo-name>.git` or download a zip and run `EXTERNAL_HEALTHCHECK=true ./scripts/start.sh`.

## 2. Install Docker & Docker Compose

```sh
sudo apt update
sudo apt install -y docker.io docker-compose
sudo systemctl enable --now docker
```

## 3. Project Structure Example

```
Laundry API/
├── backend/
│   ├── server.js
│   └── package.json
├── frontend/
│   ├── package.json
│   └── ...
├── dockerfile
├── docker-compose.yml
```

## 4. Create a Dockerfile (root of project)

```Dockerfile
# --- Frontend build stage ---
FROM node:18 AS frontend-build
WORKDIR /app/frontend
COPY frontend/package*.json ./
RUN npm install
COPY frontend/ .
RUN npm run build

# --- Backend build stage ---
FROM node:18 AS backend-build
WORKDIR /app/backend
COPY backend/package*.json ./
RUN npm install
COPY backend/ .

# --- Production image ---
FROM node:18-slim
WORKDIR /app

# Copy backend
COPY --from=backend-build /app/backend /app/backend
# Copy frontend build output into backend's public directory
COPY --from=frontend-build /app/frontend/build /app/backend/build

# Install only production dependencies for backend
WORKDIR /app/backend
RUN npm install --omit=dev

# Expose backend port
EXPOSE 5000

# Start backend server
CMD ["node", "server.js"]
```

## 5. (Optional) docker-compose.yml
If you want to use Docker Compose, create this file:

```yaml
version: '3'
services:
  laundry-app:
    build: .
    ports:
      - "5000:5000"
    volumes:
      - ./backend:/app/backend
      - ./frontend:/app/frontend
    restart: unless-stopped
```

## 6. One-step build and run with Docker Compose

Use the provided scripts for a single command deploy. Frontend is built in a builder stage and served by the backend at `/`.

Linux/macOS:

```sh
./scripts/start.sh
```

Windows (PowerShell):

```powershell
./scripts/start.ps1
```

Disable external connectivity healthcheck (optional):

```sh
EXTERNAL_HEALTHCHECK=false ./scripts/start.sh
```

```powershell
./scripts/start.ps1 -NoExternalHealth
```

Stop / Restart / Logs:

```sh
./scripts/stop.sh
./scripts/restart.sh
./scripts/logs.sh
```

```powershell
./scripts/stop.ps1
./scripts/restart.ps1
```

Health endpoints:

- Internal: GET /health (Dockerfile HEALTHCHECK uses this)
- External: GET /health/external (compose healthcheck; toggle with EXTERNAL_HEALTHCHECK)

## 6b. Build and Run the Container (manual)

```sh
cd /path/to/Laundry\ API
sudo docker build -t laundry-app .
sudo docker run -d -p 5000:5000 --name laundry laundry-app
```

Or with Docker Compose:

```sh
sudo docker compose up --build -d
```

---

# 12. Proxmox LXC: Pinned Ubuntu 24.04 one‑liner

Run on the Proxmox host shell to create a Docker‑ready CT with Ubuntu 24.04 (privileged, nesting/keyctl enabled).

```bash
CTID=102; HOSTNAME=laundryapp; STORAGE=local-lvm; DISK=8; CORES=2; MEMORY=2048; SWAP=512; BRIDGE=vmbr0; PASS='REPLACE_ME'; \
pveam update; \
TEMPLATE="ubuntu-24.04-standard_24.04-1_amd64.tar.zst"; \
pveam download local "$TEMPLATE"; \
pct create "$CTID" "local:vztmpl/${TEMPLATE}" \
  -hostname "$HOSTNAME" \
  -rootfs "${STORAGE}:${DISK}" \
  -cores "$CORES" -memory "$MEMORY" -swap "$SWAP" \
  -net0 name=eth0,bridge="$BRIDGE",ip=dhcp \
  -features nesting=1,keyctl=1 \
  -unprivileged 0 \
  -password "$PASS"; \
pct start "$CTID"; \
pct exec "$CTID" -- bash -lc "apt-get update -y && apt-get install -y docker.io docker-compose-plugin ca-certificates unzip curl && systemctl enable --now docker && docker --version && docker compose version && echo 'CT ready: ' \"\$(hostname -I)\"" 
```

Use SSH key instead of password (optional):

```bash
CTID=102; HOSTNAME=laundryapp; STORAGE=local-lvm; DISK=8; CORES=2; MEMORY=2048; SWAP=512; BRIDGE=vmbr0; PUBKEY=/root/.ssh/id_rsa.pub; \
pveam update; \
TEMPLATE="ubuntu-24.04-standard_24.04-1_amd64.tar.zst"; \
pveam download local "$TEMPLATE"; \
pct create "$CTID" "local:vztmpl/${TEMPLATE}" \
  -hostname "$HOSTNAME" \
  -rootfs "${STORAGE}:${DISK}" \
  -cores "$CORES" -memory "$MEMORY" -swap "$SWAP" \
  -net0 name=eth0,bridge="$BRIDGE",ip=dhcp \
  -features nesting=1,keyctl=1 \
  -unprivileged 0 \
  -ssh-public-keys "$PUBKEY"; \
pct start "$CTID"; \
pct exec "$CTID" -- bash -lc "apt-get update -y && apt-get install -y docker.io docker-compose-plugin ca-certificates unzip curl && systemctl enable --now docker && docker --version && docker compose version && echo 'CT ready: ' \"\$(hostname -I)\"" 
```

Teardown:

```bash
pct stop 102 || true; pct destroy 102
```

## 7. Access the App
- Backend API: http://<CT-IP>:5000
- Frontend (static build): You may need to serve the frontend build with a static server (e.g., serve or nginx) or proxy requests from backend.

## 8. Notes
- Make sure your backend serves the frontend build (e.g., using express.static in server.js) or set up a reverse proxy.
- Adjust ports as needed.
- For persistent data, mount volumes as needed.

---

You can copy this text into a file (e.g., DEPLOYMENT.md) and convert to PDF if needed.

#
# 9. Networking and Nginx Reverse Proxy Setup
#

## Expose Container Ports

- Make sure your Proxmox CT network is set to "Bridged mode" or has a routable IP so you can access it from your LAN or externally.
- The Docker container exposes port 5000 (backend). You may want to expose port 80 for the frontend via Nginx.

## Install Nginx in the CT

```sh
sudo apt update
sudo apt install -y nginx
```

## Configure Nginx as a Reverse Proxy

Edit or create a config file (e.g., `/etc/nginx/sites-available/laundry`):

```nginx
server {
  listen 80;
  server_name _;

  # Serve React frontend static files
  root /app/frontend/build;
  index index.html;

  location / {
    try_files $uri /index.html;
  }

  # Proxy API requests to backend
  location /api/ {
    proxy_pass http://localhost:5000/api/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
  }
}
```

Enable the config and restart Nginx:

```sh
sudo ln -s /etc/nginx/sites-available/laundry /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx
```

## Adjust Dockerfile (if needed)

- Make sure your Dockerfile copies the frontend build to `/app/frontend/build`.
- You may want to run only the backend in Docker and let Nginx serve the frontend build directly from the host, or use a multi-stage Docker setup.

## Access the App

- Visit `http://<CT-IP>/` for the frontend.
- API requests to `/api/` will be proxied to the backend.

---

# 10. Uploading and Running the App in Your LXC Container (Frontend + Backend together)

This project serves the built frontend from the backend. You deploy a single container that handles both.

## A) Transfer files to the LXC

Windows (PowerShell) – copy a zip:

```powershell
# From your Windows PC
scp "C:\Users\<you>\OneDrive\Projects\Coding\LaundryApp.zip" root@<LXC-IP>:/root/
```

On the LXC, unzip and enter the project:

```sh
ssh root@<LXC-IP>
unzip /root/LaundryApp.zip -d /root/
cd /root/LaundryApp
```

Alternative: copy the folder directly (Linux/macOS):

```sh
scp -r /path/to/LaundryApp root@<LXC-IP>:/root/
ssh root@<LXC-IP> "cd /root/LaundryApp && pwd"
```

## B) Ensure Docker is available inside the LXC

```sh
apt update
apt install -y docker.io docker-compose-plugin ca-certificates unzip
systemctl enable --now docker
docker --version
docker compose version
```

If using Proxmox, set the CT Options → Nesting: Enabled.

## C) One-step build and run (recommended)

```sh
# From inside /root/LaundryApp on the LXC
./scripts/start.sh
```

Disable external connectivity health gating (optional):

```sh
EXTERNAL_HEALTHCHECK=false ./scripts/start.sh
```

Stop / Restart / Logs:

```sh
./scripts/stop.sh
./scripts/restart.sh
./scripts/logs.sh
```

## D) Verify

```sh
docker ps                     # STATUS should be (healthy) if all checks pass
curl http://localhost:5000/   # frontend HTML
curl http://localhost:5000/health
curl http://localhost:5000/health/external   # can be disabled by EXTERNAL_HEALTHCHECK=false
```

## E) Manual commands (if you prefer not to use scripts)

```sh
docker compose up -d --build
# later
docker compose down -v
```

---

# 11. Updated Dockerfile and Deployment Notes

## Multi-Stage Dockerfile (Recommended)

The Dockerfile now uses a multi-stage build for a smaller, more secure image. The frontend is built separately and the static build is copied into the backend image. The backend (Express) serves the frontend build automatically.

### New Dockerfile Example

```Dockerfile
# --- Frontend build stage ---
FROM node:18 AS frontend-build
WORKDIR /app/frontend
COPY frontend/package*.json ./
RUN npm install
COPY frontend/ .
RUN npm run build

# --- Backend build stage ---
FROM node:18 AS backend-build
WORKDIR /app/backend
COPY backend/package*.json ./
RUN npm install
COPY backend/ .

# --- Production image ---
FROM node:18-slim
WORKDIR /app

# Copy backend
COPY --from=backend-build /app/backend /app/backend
# Copy frontend build output into backend's public directory
COPY --from=frontend-build /app/frontend/build /app/backend/build

# Install only production dependencies for backend
WORKDIR /app/backend
RUN npm install --omit=dev

# Expose backend port
EXPOSE 5000

# Start backend server
CMD ["node", "server.js"]
```

## Build and Run (No Compose Required)

```sh
sudo docker build -t laundry-app .
sudo docker run -d -p 5000:5000 --name laundry-app laundry-app
```

- The backend will serve the frontend at `http://<CT-IP>:5000/`.
- API requests are available at `http://<CT-IP>:5000/api/`.
