#!/bin/bash
# full-polygon-flow.sh - Complete end-to-end flow for polygon DID credential issuance
#
# This script:
# 1. Checks if services are running
# 2. Applies patches if needed
# 3. Registers the polygon DID (or uses existing)
# 4. Issues a W3C credential
# 5. Verifies the credential
#
# Usage: ./full-polygon-flow.sh [OPTIONS]
#   -c, --container NAME    Container name
#   -p, --port PORT         API port (default: 8004)
#   -k, --api-key KEY       API key for authentication
#   --skip-patches          Skip applying patches
#   --register-did          Force DID registration (even if exists)
#   -h, --help              Show this help message

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
CONTAINER="${CONTAINER:-1445b78e-092c-445c-9f83-024b4d661b22_TestaIssuer002}"
PORT="${PORT:-8004}"
API_KEY="${API_KEY:-supersecret-that-too-16chars}"
PRIVATE_KEY="${PRIVATE_KEY:-52b5fe7ac274c912b5fdd2440e846a20360d78af278d2722a79051f28b44ef3a}"
ENDPOINT="${ENDPOINT:-https://credebl.example.com}"
SKIP_PATCHES=false
REGISTER_DID=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--container)
            CONTAINER="$2"
            shift 2
            ;;
        -p|--port)
            PORT="$2"
            shift 2
            ;;
        -k|--api-key)
            API_KEY="$2"
            shift 2
            ;;
        --skip-patches)
            SKIP_PATCHES=true
            shift
            ;;
        --register-did)
            REGISTER_DID=true
            shift
            ;;
        -h|--help)
            head -20 "$0" | tail -17
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "========================================"
echo "  Polygon DID Credential Issuance Flow"
echo "========================================"
echo ""
echo "Configuration:"
echo "  Container: $CONTAINER"
echo "  Port: $PORT"
echo ""

# Step 1: Check if container is running
echo "Step 1: Checking container status..."
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    echo "[FAIL] Container '$CONTAINER' is not running"
    echo ""
    echo "Available containers:"
    docker ps --format '  - {{.Names}}'
    exit 1
fi
echo "[OK] Container is running"
echo ""

# Step 2: Apply patches if needed
if [ "$SKIP_PATCHES" = false ]; then
    echo "Step 2: Checking/applying patches..."
    PATCH_CHECK=$(docker exec "$CONTAINER" cat /app/node_modules/@ayanworks/credo-polygon-w3c-module/build/dids/PolygonDidRegistrar.js 2>/dev/null | grep -c "secp256k1-2019/v1" || echo "0")

    if [ "$PATCH_CHECK" -gt "0" ]; then
        echo "[OK] Patches already applied"
    else
        echo "Applying patches..."

        # Copy patch files
        MODULE_PATH="/app/node_modules/@ayanworks/credo-polygon-w3c-module/build/dids"
        docker cp "$SCRIPT_DIR/PolygonDidRegistrar.js" "$CONTAINER:$MODULE_PATH/PolygonDidRegistrar.js"
        docker cp "$SCRIPT_DIR/PolygonDidResolver.js" "$CONTAINER:$MODULE_PATH/PolygonDidResolver.js"
        docker cp "$SCRIPT_DIR/didPolygonUtil.js" "$CONTAINER:$MODULE_PATH/didPolygonUtil.js"

        echo "Patches applied. Restarting container..."
        docker restart "$CONTAINER"

        echo "Waiting for container to start..."
        sleep 15

        # Verify container is running
        if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
            echo "[FAIL] Container failed to restart"
            exit 1
        fi
        echo "[OK] Patches applied and container restarted"
    fi
else
    echo "Step 2: Skipping patches (--skip-patches)"
fi
echo ""

# Step 3: Get JWT token
echo "Step 3: Getting JWT token..."
for i in {1..5}; do
    JWT_RESPONSE=$(curl -s -X POST "http://localhost:$PORT/agent/token" \
        -H "Authorization: $API_KEY" 2>/dev/null)

    if echo "$JWT_RESPONSE" | grep -q "token"; then
        JWT_TOKEN=$(echo "$JWT_RESPONSE" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
        break
    fi

    echo "  Attempt $i failed, retrying in 3 seconds..."
    sleep 3
done

if [ -z "$JWT_TOKEN" ]; then
    echo "[FAIL] Could not get JWT token after 5 attempts"
    echo "Response: $JWT_RESPONSE"
    exit 1
fi
echo "[OK] JWT token obtained"
echo ""

# Step 4: Check existing DIDs or register new one
echo "Step 4: Checking/registering polygon DID..."
DIDS_RESPONSE=$(curl -s -X GET "http://localhost:$PORT/dids" \
    -H "Authorization: Bearer $JWT_TOKEN")

POLYGON_DID=$(echo "$DIDS_RESPONSE" | grep -o '"did:polygon:0x[^"]*"' | head -1 | tr -d '"')

if [ -n "$POLYGON_DID" ] && [ "$REGISTER_DID" = false ]; then
    echo "[OK] Found existing polygon DID: $POLYGON_DID"
else
    echo "Registering new polygon DID..."

    REGISTER_PAYLOAD=$(cat <<EOF
{
    "method": "polygon",
    "network": "polygon:mainnet",
    "endpoint": "$ENDPOINT",
    "privatekey": "$PRIVATE_KEY"
}
EOF
)

    REGISTER_RESPONSE=$(curl -s -X POST "http://localhost:$PORT/dids/write" \
        -H "Authorization: Bearer $JWT_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$REGISTER_PAYLOAD")

    if echo "$REGISTER_RESPONSE" | grep -q '"state":"finished"\|did:polygon'; then
        POLYGON_DID=$(echo "$REGISTER_RESPONSE" | grep -o 'did:polygon:0x[^"]*' | head -1)
        echo "[OK] DID registered: $POLYGON_DID"
    else
        echo "[WARN] DID registration response:"
        echo "$REGISTER_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$REGISTER_RESPONSE"

        # Try to extract DID anyway
        POLYGON_DID=$(echo "$REGISTER_RESPONSE" | grep -o 'did:polygon:0x[^"]*' | head -1)
        if [ -z "$POLYGON_DID" ]; then
            # Check DIDs again
            DIDS_RESPONSE=$(curl -s -X GET "http://localhost:$PORT/dids" \
                -H "Authorization: Bearer $JWT_TOKEN")
            POLYGON_DID=$(echo "$DIDS_RESPONSE" | grep -o '"did:polygon:0x[^"]*"' | head -1 | tr -d '"')
        fi

        if [ -z "$POLYGON_DID" ]; then
            echo "[FAIL] Could not register or find polygon DID"
            exit 1
        fi
        echo "[OK] Using DID: $POLYGON_DID"
    fi
fi
echo ""

# Step 5: Issue credential
echo "Step 5: Issuing W3C Verifiable Credential..."
ISSUANCE_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

CREDENTIAL_PAYLOAD=$(cat <<EOF
{
    "credential": {
        "@context": [
            "https://www.w3.org/2018/credentials/v1"
        ],
        "type": ["VerifiableCredential"],
        "issuer": "$POLYGON_DID",
        "issuanceDate": "$ISSUANCE_DATE",
        "credentialSubject": {
            "id": "did:example:holder",
            "name": "Test Subject",
            "issuedVia": "polygon-did-flow"
        }
    },
    "verificationMethod": "${POLYGON_DID}#key-1",
    "proofType": "EcdsaSecp256k1Signature2019"
}
EOF
)

SIGN_RESPONSE=$(curl -s -X POST "http://localhost:$PORT/agent/credential/sign?storeCredential=true&dataTypeToSign=jsonLd" \
    -H "Authorization: Bearer $JWT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$CREDENTIAL_PAYLOAD")

if ! echo "$SIGN_RESPONSE" | grep -q '"proof"'; then
    echo "[FAIL] Credential signing failed"
    echo "Response: $SIGN_RESPONSE"
    exit 1
fi
echo "[OK] Credential signed successfully"

# Extract just the credential from the API response wrapper
SIGNED_CREDENTIAL=$(echo "$SIGN_RESPONSE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if 'credential' in data:
    print(json.dumps(data['credential']))
else:
    print(json.dumps(data))
" 2>/dev/null || echo "$SIGN_RESPONSE")

# Save credential
CREDENTIAL_FILE="/tmp/polygon-credential-$(date +%s).json"
echo "$SIGNED_CREDENTIAL" > "$CREDENTIAL_FILE"
echo "    Saved to: $CREDENTIAL_FILE"
echo ""

# Step 6: Verify credential
echo "Step 6: Verifying credential..."
VERIFY_PAYLOAD="{\"credential\": $SIGNED_CREDENTIAL}"

VERIFY_RESPONSE=$(curl -s -X POST "http://localhost:$PORT/agent/credential/verify" \
    -H "Authorization: Bearer $JWT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$VERIFY_PAYLOAD")

if echo "$VERIFY_RESPONSE" | grep -qi '"verified":\s*true\|"isValid":\s*true\|"valid":\s*true'; then
    echo "[OK] Credential verification PASSED"
else
    echo "[WARN] Verification result:"
    echo "$VERIFY_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$VERIFY_RESPONSE"
fi
echo ""

# Summary
echo "========================================"
echo "           Flow Complete!"
echo "========================================"
echo ""
echo "Summary:"
echo "  DID: $POLYGON_DID"
echo "  Credential: $CREDENTIAL_FILE"
echo "  Proof Type: EcdsaSecp256k1Signature2019"
echo ""
echo "Signed Credential:"
echo "$SIGNED_CREDENTIAL" | python3 -m json.tool 2>/dev/null || echo "$SIGNED_CREDENTIAL"
