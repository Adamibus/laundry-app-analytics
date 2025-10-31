#!/usr/bin/env bash
set -euo pipefail

./scripts/stop.sh || true
./scripts/start.sh
