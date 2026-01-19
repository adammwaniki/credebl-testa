#!/bin/bash
# check-services.sh - Verify CREDEBL services are running and healthy
#
# Usage: ./check-services.sh [CONTAINER_NAME] [PORT]
# Default container: 1445b78e-092c-445c-9f83-024b4d661b22_TestaIssuer002
# Default port: 8004

set -e

CONTAINER="${1:-1445b78e-092c-445c-9f83-024b4d661b22_TestaIssuer002}"
PORT="${2:-8004}"
API_KEY="${API_KEY:-supersecret-that-too-16chars}"

echo "=== CREDEBL Service Health Check ==="
echo "Container: $CONTAINER"
echo "Port: $PORT"
echo ""

# Check if container is running
echo "1. Checking container status..."
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    echo "   [OK] Container is running"
else
    echo "   [FAIL] Container '$CONTAINER' is not running"
    echo ""
    echo "   Available containers:"
    docker ps --format '   - {{.Names}}'
    exit 1
fi

# Check container health
echo ""
echo "2. Checking container health..."
HEALTH=$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null || echo "no-healthcheck")
if [ "$HEALTH" = "healthy" ]; then
    echo "   [OK] Container health: $HEALTH"
elif [ "$HEALTH" = "no-healthcheck" ]; then
    echo "   [WARN] No health check configured, checking manually..."
else
    echo "   [WARN] Container health: $HEALTH"
fi

# Check if API is responding
echo ""
echo "3. Checking API connectivity..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$PORT/agent/health" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    echo "   [OK] API is responding (HTTP $HTTP_CODE)"
elif [ "$HTTP_CODE" = "000" ]; then
    echo "   [FAIL] Cannot connect to API on port $PORT"
    exit 1
else
    echo "   [WARN] API responded with HTTP $HTTP_CODE"
fi

# Check JWT token generation
echo ""
echo "4. Checking JWT authentication..."
JWT_RESPONSE=$(curl -s -X POST "http://localhost:$PORT/agent/token" \
    -H "Authorization: $API_KEY" 2>/dev/null)

if echo "$JWT_RESPONSE" | grep -q "token"; then
    echo "   [OK] JWT token generation working"
    JWT_TOKEN=$(echo "$JWT_RESPONSE" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
else
    echo "   [FAIL] JWT token generation failed"
    echo "   Response: $JWT_RESPONSE"
    exit 1
fi

# Check DID resolution capability
echo ""
echo "5. Checking DID resolution..."
DID_RESPONSE=$(curl -s -X GET "http://localhost:$PORT/dids" \
    -H "Authorization: Bearer $JWT_TOKEN" 2>/dev/null)

if echo "$DID_RESPONSE" | grep -q "did:"; then
    DID_COUNT=$(echo "$DID_RESPONSE" | grep -o '"did:' | wc -l)
    echo "   [OK] DID resolution working ($DID_COUNT DIDs found)"
else
    echo "   [WARN] No DIDs found or DID resolution issue"
    echo "   Response: $DID_RESPONSE"
fi

# Check if patches are applied
echo ""
echo "6. Checking patch status..."
PATCH_CHECK=$(docker exec "$CONTAINER" cat /app/node_modules/@ayanworks/credo-polygon-w3c-module/build/dids/PolygonDidRegistrar.js 2>/dev/null | grep -c "secp256k1-2019/v1" || echo "0")
if [ "$PATCH_CHECK" -gt "0" ]; then
    echo "   [OK] Polygon DID patches are applied"
else
    echo "   [WARN] Polygon DID patches may not be applied"
    echo "   Run ./apply-patches.sh to apply patches"
fi

echo ""
echo "=== Health Check Complete ==="
echo ""
echo "Summary:"
echo "  Container: Running"
echo "  API: Responsive"
echo "  Auth: Working"
echo "  Patches: $([ "$PATCH_CHECK" -gt "0" ] && echo "Applied" || echo "Not Applied")"
echo ""

# Export JWT token for use by other scripts
if [ -n "$JWT_TOKEN" ]; then
    echo "JWT Token (for other scripts):"
    echo "export JWT_TOKEN=\"$JWT_TOKEN\""
fi
