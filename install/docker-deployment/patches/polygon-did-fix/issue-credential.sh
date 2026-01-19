#!/bin/bash
# issue-credential.sh - Issue a W3C Verifiable Credential using did:polygon
#
# Usage: ./issue-credential.sh [OPTIONS]
#   -p, --port PORT         API port (default: 8004)
#   -k, --api-key KEY       API key for authentication
#   -d, --did DID           Issuer DID (default: did:polygon:0xD3A288e4cCeb5ADE57c5B674475d6728Af3bD9Fd)
#   -s, --subject-id ID     Subject DID (default: did:example:holder)
#   -n, --subject-name NAME Subject name (default: "Test Subject")
#   -v, --verify            Verify the credential after issuance
#   -h, --help              Show this help message

set -e

# Default values
PORT="8004"
API_KEY="${API_KEY:-supersecret-that-too-16chars}"
ISSUER_DID="did:polygon:0xD3A288e4cCeb5ADE57c5B674475d6728Af3bD9Fd"
SUBJECT_ID="did:example:holder"
SUBJECT_NAME="Test Subject"
VERIFY_CREDENTIAL=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--port)
            PORT="$2"
            shift 2
            ;;
        -k|--api-key)
            API_KEY="$2"
            shift 2
            ;;
        -d|--did)
            ISSUER_DID="$2"
            shift 2
            ;;
        -s|--subject-id)
            SUBJECT_ID="$2"
            shift 2
            ;;
        -n|--subject-name)
            SUBJECT_NAME="$2"
            shift 2
            ;;
        -v|--verify)
            VERIFY_CREDENTIAL=true
            shift
            ;;
        -h|--help)
            head -17 "$0" | tail -14
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "=== W3C Credential Issuance (did:polygon) ==="
echo "Port: $PORT"
echo "Issuer DID: $ISSUER_DID"
echo "Subject ID: $SUBJECT_ID"
echo ""

# Get JWT token
echo "1. Getting JWT token..."
JWT_RESPONSE=$(curl -s -X POST "http://localhost:$PORT/agent/token" \
    -H "Authorization: $API_KEY")

if ! echo "$JWT_RESPONSE" | grep -q "token"; then
    echo "   [FAIL] Failed to get JWT token"
    echo "   Response: $JWT_RESPONSE"
    exit 1
fi

JWT_TOKEN=$(echo "$JWT_RESPONSE" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
echo "   [OK] JWT token obtained"

# Generate issuance date
ISSUANCE_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Create credential payload
echo ""
echo "2. Signing credential..."
CREDENTIAL_PAYLOAD=$(cat <<EOF
{
    "credential": {
        "@context": [
            "https://www.w3.org/2018/credentials/v1"
        ],
        "type": ["VerifiableCredential"],
        "issuer": "$ISSUER_DID",
        "issuanceDate": "$ISSUANCE_DATE",
        "credentialSubject": {
            "id": "$SUBJECT_ID",
            "name": "$SUBJECT_NAME"
        }
    },
    "verificationMethod": "${ISSUER_DID}#key-1",
    "proofType": "EcdsaSecp256k1Signature2019"
}
EOF
)

SIGN_RESPONSE=$(curl -s -X POST "http://localhost:$PORT/agent/credential/sign?storeCredential=true&dataTypeToSign=jsonLd" \
    -H "Authorization: Bearer $JWT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$CREDENTIAL_PAYLOAD")

if echo "$SIGN_RESPONSE" | grep -q '"proof"'; then
    echo "   [OK] Credential signed successfully!"

    # Extract just the credential from the API response wrapper
    SIGNED_CREDENTIAL=$(echo "$SIGN_RESPONSE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if 'credential' in data:
    print(json.dumps(data['credential'], indent=2))
else:
    print(json.dumps(data, indent=2))
" 2>/dev/null || echo "$SIGN_RESPONSE")

    echo ""
    echo "=== Signed Credential ==="
    echo "$SIGNED_CREDENTIAL"

    # Save credential to file
    CREDENTIAL_FILE="/tmp/polygon-credential-$(date +%s).json"
    echo "$SIGNED_CREDENTIAL" > "$CREDENTIAL_FILE"
    echo ""
    echo "Credential saved to: $CREDENTIAL_FILE"
else
    echo "   [FAIL] Credential signing failed"
    echo "   Response: $SIGN_RESPONSE"
    exit 1
fi

# Verify credential if requested
if [ "$VERIFY_CREDENTIAL" = true ]; then
    echo ""
    echo "3. Verifying credential..."

    VERIFY_PAYLOAD="{\"credential\": $SIGNED_CREDENTIAL}"

    VERIFY_RESPONSE=$(curl -s -X POST "http://localhost:$PORT/agent/credential/verify" \
        -H "Authorization: Bearer $JWT_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$VERIFY_PAYLOAD")

    if echo "$VERIFY_RESPONSE" | grep -qi '"verified":\s*true\|"isValid":\s*true\|"valid":\s*true'; then
        echo "   [OK] Credential verification PASSED"
        echo ""
        echo "=== Verification Result ==="
        echo "$VERIFY_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$VERIFY_RESPONSE"
    else
        echo "   [WARN] Credential verification result:"
        echo "$VERIFY_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$VERIFY_RESPONSE"
    fi
fi

echo ""
echo "=== Credential Issuance Complete ==="
