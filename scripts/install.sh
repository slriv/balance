#!/usr/bin/env bash
# balance install script
# Usage: ./install.sh [IMAGE_TAR]
# IMAGE_TAR defaults to ../balance-tv.tar beside the extracted release, or a
# co-located balance-tv.tar beside this script.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOCAL_IMAGE_TAR="$SCRIPT_DIR/balance-tv.tar"
PACKAGE_IMAGE_TAR="$PACKAGE_ROOT/balance-tv.tar"
ENV_TEMPLATE="$PACKAGE_ROOT/.env.example"
IMAGE_TAR="${1:-}"

if [[ -z "$IMAGE_TAR" ]]; then
    if [[ -f "$PACKAGE_IMAGE_TAR" ]]; then
        IMAGE_TAR="$PACKAGE_IMAGE_TAR"
    elif [[ -f "$LOCAL_IMAGE_TAR" ]]; then
        IMAGE_TAR="$LOCAL_IMAGE_TAR"
    else
        echo "ERROR: Docker image tar not found. Expected '$PACKAGE_IMAGE_TAR' or '$LOCAL_IMAGE_TAR', or pass IMAGE_TAR explicitly." >&2
        exit 1
    fi
fi

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: $1 is required but not found" >&2; exit 1; }; }
need_cmd docker

echo "==> Loading Docker image from $IMAGE_TAR"
docker load -i "$IMAGE_TAR"

if [[ ! -f .env ]]; then
    echo "==> Creating .env from template"
    cp "$ENV_TEMPLATE" .env
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
