#!/bin/bash
# apply-patches.sh - Apply polygon DID patches to a credo agent container
#
# Usage: ./apply-patches.sh [CONTAINER_NAME]
# Default container: 1445b78e-092c-445c-9f83-024b4d661b22_TestaIssuer002

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER="${1:-1445b78e-092c-445c-9f83-024b4d661b22_TestaIssuer002}"
MODULE_PATH="/app/node_modules/@ayanworks/credo-polygon-w3c-module/build/dids"

echo "=== Polygon DID Patch Applicator ==="
echo "Container: $CONTAINER"
echo "Patch directory: $SCRIPT_DIR"
echo ""

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    echo "ERROR: Container '$CONTAINER' is not running"
    echo "Available containers:"
    docker ps --format '{{.Names}}'
    exit 1
fi

echo "Applying patches..."

# Apply PolygonDidRegistrar.js
echo "  - PolygonDidRegistrar.js"
docker cp "$SCRIPT_DIR/PolygonDidRegistrar.js" "$CONTAINER:$MODULE_PATH/PolygonDidRegistrar.js"

# Apply PolygonDidResolver.js
echo "  - PolygonDidResolver.js"
docker cp "$SCRIPT_DIR/PolygonDidResolver.js" "$CONTAINER:$MODULE_PATH/PolygonDidResolver.js"

# Apply didPolygonUtil.js
echo "  - didPolygonUtil.js"
docker cp "$SCRIPT_DIR/didPolygonUtil.js" "$CONTAINER:$MODULE_PATH/didPolygonUtil.js"

echo ""
echo "Patches applied successfully!"
echo ""
echo "NOTE: You need to restart the container for patches to take effect:"
echo "  docker restart $CONTAINER"
echo ""

read -p "Restart container now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Restarting container..."
    docker restart "$CONTAINER"
    echo "Waiting for container to start..."
    sleep 15

    # Verify container is running
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
        echo "Container restarted successfully!"
    else
        echo "WARNING: Container may not have started properly"
        docker logs "$CONTAINER" --tail 20
    fi
fi
