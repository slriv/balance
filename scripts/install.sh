#!/usr/bin/env bash
# balance install script
# Usage: ./install.sh [IMAGE_TAR]
# IMAGE_TAR defaults to balance-tv.tar in the same directory as this script.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_TAR="${1:-$SCRIPT_DIR/balance-tv.tar}"

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: $1 is required but not found" >&2; exit 1; }; }
need_cmd docker

echo "==> Loading Docker image from $IMAGE_TAR"
docker load -i "$IMAGE_TAR"

if [[ ! -f .env ]]; then
    echo "==> Creating .env from template"
    cp "$SCRIPT_DIR/.env.example" .env
    echo ""
    echo "IMPORTANT: Edit .env before starting services:"
    echo "  - Set TV_PATH_1..TV_PATH_4 to your media mount paths"
    echo "  - Set SONARR_BASE_URL, SONARR_API_KEY"
    echo "  - Set PLEX_BASE_URL, PLEX_TOKEN"
    echo ""
fi

mkdir -p artifacts config

echo "==> Image loaded. Start the web UI with:"
echo "    docker compose up -d balance_web"
echo ""
echo "    Then open http://localhost:\${BALANCE_WEB_PORT:-8080}"
