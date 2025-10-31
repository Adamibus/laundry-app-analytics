#!/usr/bin/env bash
set -euo pipefail

# Detect docker compose CLI (plugin or standalone)
if docker compose version >/dev/null 2>&1; then
	DCMD=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
	DCMD=(docker-compose)
else
	echo "ERROR: docker compose/docker-compose not found." >&2
	exit 1
fi

echo "Stopping and removing stack..."
"${DCMD[@]}" down -v
