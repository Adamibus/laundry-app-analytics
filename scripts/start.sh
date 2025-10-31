#!/usr/bin/env bash
set -euo pipefail
# Optional: disable external healthcheck by setting EXTERNAL_HEALTHCHECK=false
export EXTERNAL_HEALTHCHECK=${EXTERNAL_HEALTHCHECK:-true}

# Detect docker compose CLI (plugin or standalone)
if docker compose version >/dev/null 2>&1; then
	DCMD=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
	DCMD=(docker-compose)
else
	echo "ERROR: docker compose/docker-compose not found. Install docker-compose-plugin or docker-compose." >&2
	exit 1
fi

echo "Building and starting stack (EXTERNAL_HEALTHCHECK=${EXTERNAL_HEALTHCHECK})..."
"${DCMD[@]}" up -d --build

echo "Done. Status:"
docker ps --filter name=laundry-app
