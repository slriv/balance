#!/bin/bash
# deploy-sandbox.sh
# Quick local sandbox deployment for testing balance web UI without Sonarr/Plex

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=========================================="
echo "Balance Sandbox Deployment"
echo "=========================================="
echo ""

# Check prerequisites
if ! command -v docker &> /dev/null; then
    echo "❌ Docker not found. Please install Docker."
    exit 1
fi

echo "✓ Docker available: $(docker --version)"
echo ""

# Create directories
echo "📁 Creating artifact directories..."
mkdir -p "$PROJECT_ROOT/artifacts/jobs"
mkdir -p "$PROJECT_ROOT/config"
echo "✓ Directories created"
echo ""

# Check for image
echo "🔍 Checking for balance-tv:local image..."
if ! docker image inspect balance-tv:local &> /dev/null; then
    echo "❌ Image not found. Please run: make build"
    exit 1
fi
echo "✓ Image found"
echo ""

# Stop any existing container
CONTAINER_NAME="balance-web-sandbox"
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "⏹  Stopping existing container..."
    docker stop "$CONTAINER_NAME" &> /dev/null || true
    docker rm "$CONTAINER_NAME" &> /dev/null || true
    sleep 1
    echo "✓ Container stopped"
fi
echo ""

# Start web service
echo "🚀 Starting balance_web service..."
docker run -d \
    --name "$CONTAINER_NAME" \
    -p 8080:8080 \
    --entrypoint balance_web \
    -v "$(cd "$PROJECT_ROOT" && pwd)/artifacts:/artifacts" \
    -v "$(cd "$PROJECT_ROOT" && pwd)/config:/config" \
    -e BALANCE_JOB_DB=/artifacts/balance-jobs.db \
    -e BALANCE_JOB_LOG_DIR=/artifacts/jobs \
    balance-tv:local daemon -l 'http://*:8080'

sleep 2

if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "❌ Container failed to start. Check logs:"
    docker logs "$CONTAINER_NAME"
    exit 1
fi

echo "✓ Service started (container: $CONTAINER_NAME)"
echo ""

# Verify service is responsive
echo "✓ Waiting for service to be ready..."
for i in {1..30}; do
    if curl -s http://localhost:8080/ > /dev/null 2>&1; then
        echo "✓ Service is responsive"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "⚠️  Service took longer than expected. Check logs:"
        docker logs "$CONTAINER_NAME"
    fi
    sleep 1
done
echo ""

# Display information
echo "=========================================="
echo "🎉 Sandbox Deployment Complete!"
echo "=========================================="
echo ""
echo "Web UI: http://localhost:8080"
echo "Container: $CONTAINER_NAME"
echo ""
echo "Usage:"
echo "  • Open http://localhost:8080 in your browser"
echo "  • View logs: docker logs -f $CONTAINER_NAME"
echo "  • Stop: docker stop $CONTAINER_NAME"
echo "  • Remove: docker rm $CONTAINER_NAME"
echo ""
echo "Note: Job stores artifacts in $PROJECT_ROOT/artifacts/"
echo ""
