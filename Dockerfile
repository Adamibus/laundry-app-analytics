# Multi-stage build for Conn College Laundry Analytics

# --- Frontend build stage ---
FROM node:20 AS frontend-build
WORKDIR /app/frontend
# Upgrade npm to latest version
RUN npm install -g npm@latest
COPY frontend/package*.json ./
RUN npm install
COPY frontend/ .
RUN chmod -R +x node_modules/.bin
RUN npm run build

# --- Backend build stage ---
FROM node:20 AS backend-build
WORKDIR /app/backend
# Upgrade npm to latest version
RUN npm install -g npm@latest
COPY backend/package*.json ./
RUN npm install
COPY backend/ .

# --- Production image ---
FROM node:20-slim
WORKDIR /app

# Set production environment for runtime
ENV NODE_ENV=production

# Install only production dependencies for backend
WORKDIR /app/backend
COPY backend/package*.json ./
RUN npm install --omit=dev

# Copy backend source code
COPY backend/. .

# Copy frontend build output into backend's build directory
COPY --from=frontend-build /app/frontend/build ./build

# Expose backend port
EXPOSE 5000

# Internal healthcheck: app must respond on /health
HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
	CMD node -e "require('http').get('http://localhost:5000/health', r => process.exit(r.statusCode===200?0:1)).on('error', () => process.exit(1));"

# Start backend server
CMD ["node", "server.js"]
