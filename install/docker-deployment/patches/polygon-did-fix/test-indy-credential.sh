#!/bin/bash
# test-indy-credential.sh - Test did:indy W3C credential verification through adapter
#
# This script tests the verification flow for W3C JSON-LD credentials issued by did:indy DIDs.
# It can either:
#   1. Issue a real credential via CREDEBL Agent (if configured with did:indy org)
#   2. Use a mock did:indy credential for testing adapter routing
#
# Usage: ./test-indy-credential.sh [OPTIONS]
#   -m, --mode MODE              Mode: 'mock' or 'issue' (default: mock)
#   -p, --agent-port PORT        Agent port (default: 8004)
#   -a, --adapter-port PORT      Adapter port (default: 8085)
#   -k, --api-key KEY            API key for authentication
#   -d, --issuer-did DID         Issuer DID (for issue mode)
#   --name NAME                  Subject name (default: Test User)
#   --network NETWORK            Indy network: bcovrin:testnet, indicio:testnet, etc.
#   -v, --verify                 Verify via adapter after creation
#   -q, --qr                     Generate QR code
#   -o, --output FILE            Save credential to file
#   -h, --help                   Show this help message
#
# Examples:
#   # Test with mock credential (no agent needed)
#   ./test-indy-credential.sh --mode mock -v
#
#   # Issue real credential via CREDEBL
#   ./test-indy-credential.sh --mode issue -d "did:indy:bcovrin:testnet:ABC123" -v -q
#
#   # Test adapter routing to CREDEBL agent
#   ./test-indy-credential.sh --mode mock -v --adapter-port 8085

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
MODE="mock"
AGENT_PORT="8004"
ADAPTER_PORT="8085"
API_KEY="${API_KEY:-supersecret-that-too-16chars}"
ISSUER_DID=""
SUBJECT_NAME="Test User"
INDY_NETWORK="bcovrin:testnet"
VERIFY_CREDENTIAL=false
GENERATE_QR=false
OUTPUT_FILE=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -m|--mode)
            MODE="$2"
            shift 2
            ;;
        -p|--agent-port)
            AGENT_PORT="$2"
            shift 2
            ;;
        -a|--adapter-port)
            ADAPTER_PORT="$2"
            shift 2
            ;;
        -k|--api-key)
            API_KEY="$2"
            shift 2
            ;;
        -d|--issuer-did)
            ISSUER_DID="$2"
            shift 2
            ;;
        --name)
            SUBJECT_NAME="$2"
            shift 2
            ;;
        --network)
            INDY_NETWORK="$2"
            shift 2
            ;;
        -v|--verify)
            VERIFY_CREDENTIAL=true
            shift
            ;;
        -q|--qr)
            GENERATE_QR=true
            shift
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -h|--help)
            head -35 "$0" | tail -32
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo ""
echo -e "${BLUE}==========================================="
echo "  did:indy W3C Credential Test"
echo -e "===========================================${NC}"
echo ""

# ============================================================================
# MOCK CREDENTIAL GENERATION
# ============================================================================

generate_mock_credential() {
    local network="$1"
    local subject_name="$2"

    # Generate a realistic-looking did:indy DID
    # Format: did:indy:<network>:<nym>
    local nym=$(echo -n "mock-issuer-$(date +%s)" | md5sum | cut -c1-22 | tr '[:lower:]' '[:upper:]')
    local mock_did="did:indy:${network}:${nym}"

    # Print status to stderr so it doesn't mix with JSON output
    echo -e "${YELLOW}Generating mock did:indy credential...${NC}" >&2
    echo "  Issuer DID: $mock_did" >&2
    echo "  Network: $network" >&2
    echo "" >&2

    local issuance_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local subject_id="did:example:holder:$(echo -n "$subject_name" | md5sum | cut -c1-16)"

    # Create a mock signed credential (output to stdout only)
    # Note: This has a mock proof - real verification will fail but adapter routing can be tested
    cat <<EOF
{
    "@context": [
        "https://www.w3.org/2018/credentials/v1",
        "https://w3id.org/security/suites/ed25519-2020/v1",
        {
            "EducationCredential": "https://schema.org/EducationalOccupationalCredential",
            "alumniOf": "https://schema.org/alumniOf",
            "degree": "https://schema.org/degree",
            "name": "https://schema.org/name",
            "dateAwarded": "https://schema.org/dateCreated"
        }
    ],
    "id": "urn:uuid:$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)",
    "type": ["VerifiableCredential", "EducationCredential"],
    "issuer": "${mock_did}",
    "issuanceDate": "${issuance_date}",
    "credentialSubject": {
        "id": "${subject_id}",
        "name": "${subject_name}",
        "alumniOf": "University of Blockchain Studies",
        "degree": "Bachelor of Decentralized Systems",
        "dateAwarded": "2024-06-15"
    },
    "proof": {
        "type": "Ed25519Signature2020",
        "created": "${issuance_date}",
        "verificationMethod": "${mock_did}#key-1",
        "proofPurpose": "assertionMethod",
        "proofValue": "z58DAdFfa9SkqZMVPxAQpic7ndTw7J69kDK3sMBtXZBhSvMgXUBLzjcBf4EAqL9LJh3V5A8D5k1XSjL3RBhYMCVvB"
    }
}
EOF
}

# ============================================================================
# REAL CREDENTIAL ISSUANCE VIA CREDEBL
# ============================================================================

issue_real_credential() {
    local issuer_did="$1"
    local subject_name="$2"

    echo -e "${YELLOW}Issuing real credential via CREDEBL Agent...${NC}"
    echo "  Issuer DID: $issuer_did"
    echo ""

    # Get JWT token
    echo "1. Getting JWT token..."
    JWT_RESPONSE=$(curl -s -X POST "http://localhost:$AGENT_PORT/agent/token" \
        -H "Authorization: $API_KEY" 2>/dev/null)

    if ! echo "$JWT_RESPONSE" | grep -q "token"; then
        echo -e "   ${RED}[FAIL] Failed to get JWT token${NC}"
        echo "   Response: $JWT_RESPONSE"
        echo ""
        echo -e "${YELLOW}Hint: Make sure CREDEBL Agent is running on port $AGENT_PORT${NC}"
        echo "      Or use --mode mock to test with mock credentials"
        exit 1
    fi

    JWT_TOKEN=$(echo "$JWT_RESPONSE" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
    echo -e "   ${GREEN}[OK] JWT token obtained${NC}"

    # Build credential payload
    local issuance_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local subject_id="did:example:holder:$(echo -n "$subject_name" | md5sum | cut -c1-16)"

    CREDENTIAL_PAYLOAD=$(cat <<EOF
{
    "credential": {
        "@context": [
            "https://www.w3.org/2018/credentials/v1",
            {
                "EducationCredential": "https://schema.org/EducationalOccupationalCredential",
                "alumniOf": "https://schema.org/alumniOf",
                "degree": "https://schema.org/degree",
                "name": "https://schema.org/name",
                "dateAwarded": "https://schema.org/dateCreated"
            }
        ],
        "type": ["VerifiableCredential", "EducationCredential"],
        "issuer": "${issuer_did}",
        "issuanceDate": "${issuance_date}",
        "credentialSubject": {
            "id": "${subject_id}",
            "name": "${subject_name}",
            "alumniOf": "University of Blockchain Studies",
            "degree": "Bachelor of Decentralized Systems",
            "dateAwarded": "2024-06-15"
        }
    },
    "verificationMethod": "${issuer_did}#key-1",
    "proofType": "Ed25519Signature2018"
}
EOF
)

    # Sign the credential
    echo ""
    echo "2. Signing credential..."
    SIGN_RESPONSE=$(curl -s -X POST "http://localhost:$AGENT_PORT/agent/credential/sign?storeCredential=true&dataTypeToSign=jsonLd" \
        -H "Authorization: Bearer $JWT_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$CREDENTIAL_PAYLOAD" 2>/dev/null)

    if ! echo "$SIGN_RESPONSE" | grep -q '"proof"'; then
        echo -e "   ${RED}[FAIL] Credential signing failed${NC}"
        echo "   Response: $SIGN_RESPONSE"
        exit 1
    fi

    echo -e "   ${GREEN}[OK] Credential signed successfully!${NC}"

    # Extract the credential
    echo "$SIGN_RESPONSE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if 'credential' in data:
    print(json.dumps(data['credential'], indent=2))
else:
    print(json.dumps(data, indent=2))
" 2>/dev/null || echo "$SIGN_RESPONSE"
}

# ============================================================================
# MAIN LOGIC
# ============================================================================

# Generate or issue credential based on mode
if [ "$MODE" = "mock" ]; then
    CREDENTIAL=$(generate_mock_credential "$INDY_NETWORK" "$SUBJECT_NAME")
elif [ "$MODE" = "issue" ]; then
    if [ -z "$ISSUER_DID" ]; then
        echo -e "${RED}ERROR: --issuer-did is required for issue mode${NC}"
        echo ""
        echo "Example: ./test-indy-credential.sh --mode issue -d 'did:indy:bcovrin:testnet:ABC123'"
        exit 1
    fi
    CREDENTIAL=$(issue_real_credential "$ISSUER_DID" "$SUBJECT_NAME")
else
    echo -e "${RED}ERROR: Invalid mode '$MODE'. Use 'mock' or 'issue'${NC}"
    exit 1
fi

# Save credential to file
if [ -z "$OUTPUT_FILE" ]; then
    OUTPUT_FILE="/tmp/indy-credential-$(date +%s).json"
fi
echo "$CREDENTIAL" > "$OUTPUT_FILE"
echo -e "${GREEN}Credential saved to: $OUTPUT_FILE${NC}"

# Display the credential
echo ""
echo -e "${BLUE}==========================================="
echo "  Credential Details"
echo -e "===========================================${NC}"
echo ""
echo "$CREDENTIAL" | python3 -m json.tool 2>/dev/null || echo "$CREDENTIAL"

# ============================================================================
# VERIFICATION VIA ADAPTER
# ============================================================================

if [ "$VERIFY_CREDENTIAL" = true ]; then
    echo ""
    echo -e "${BLUE}==========================================="
    echo "  Verification via Adapter"
    echo -e "===========================================${NC}"
    echo ""

    # Check adapter health first
    echo "1. Checking adapter health..."
    HEALTH_RESPONSE=$(curl -s "http://localhost:$ADAPTER_PORT/health" 2>/dev/null)

    if [ -z "$HEALTH_RESPONSE" ]; then
        echo -e "   ${RED}[FAIL] Adapter not reachable on port $ADAPTER_PORT${NC}"
        echo ""
        echo "   Start the adapter with:"
        echo "   node offline-adapter.js"
        exit 1
    fi

    CONNECTIVITY=$(echo "$HEALTH_RESPONSE" | grep -o '"connectivity":"[^"]*"' | cut -d'"' -f4)
    echo -e "   ${GREEN}[OK] Adapter is running (connectivity: $CONNECTIVITY)${NC}"

    # Submit credential for verification
    echo ""
    echo "2. Submitting credential to adapter..."
    echo "   POST http://localhost:$ADAPTER_PORT/v1/verify/vc-verification"

    VERIFY_PAYLOAD="{\"verifiableCredentials\": [$CREDENTIAL]}"

    VERIFY_RESPONSE=$(curl -s -X POST "http://localhost:$ADAPTER_PORT/v1/verify/vc-verification" \
        -H "Content-Type: application/json" \
        -d "$VERIFY_PAYLOAD" 2>/dev/null)

    echo ""
    echo "3. Verification Response:"
    echo "$VERIFY_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$VERIFY_RESPONSE"

    # Parse result
    STATUS=$(echo "$VERIFY_RESPONSE" | grep -o '"verificationStatus":"[^"]*"' | cut -d'"' -f4)
    BACKEND=$(echo "$VERIFY_RESPONSE" | grep -o '"backend":"[^"]*"' | cut -d'"' -f4)
    OFFLINE=$(echo "$VERIFY_RESPONSE" | grep -o '"offline":[^,}]*' | cut -d':' -f2)

    echo ""
    if [ "$STATUS" = "SUCCESS" ]; then
        echo -e "${GREEN}============================================"
        echo "  VERIFICATION RESULT: SUCCESS"
        echo -e "============================================${NC}"
    elif [ "$STATUS" = "UNKNOWN_ISSUER" ]; then
        echo -e "${YELLOW}============================================"
        echo "  VERIFICATION RESULT: UNKNOWN_ISSUER"
        echo "============================================"
        echo ""
        echo "  The issuer is not in the cache."
        echo "  For mock credentials, this is expected."
        echo ""
        echo "  To sync the issuer (for real DIDs):"
        echo "  curl -X POST http://localhost:$ADAPTER_PORT/sync \\"
        echo "    -H 'Content-Type: application/json' \\"
        echo -e "    -d '{\"did\": \"<issuer-did>\"}'${NC}"
    else
        echo -e "${RED}============================================"
        echo "  VERIFICATION RESULT: $STATUS"
        echo -e "============================================${NC}"
    fi

    echo ""
    echo "Backend: ${BACKEND:-N/A}"
    echo "Offline: ${OFFLINE:-N/A}"
fi

# ============================================================================
# QR CODE GENERATION
# ============================================================================

if [ "$GENERATE_QR" = true ]; then
    echo ""
    echo -e "${BLUE}==========================================="
    echo "  QR Code Generation"
    echo -e "===========================================${NC}"
    echo ""

    PIXELPASS_DIR="/tmp/pixelpass_env"

    # Ensure PixelPass is installed
    if [ ! -d "$PIXELPASS_DIR/node_modules/@injistack/pixelpass" ]; then
        echo "Installing PixelPass..."
        mkdir -p "$PIXELPASS_DIR"
        (cd "$PIXELPASS_DIR" && npm init -y > /dev/null 2>&1 && npm install @injistack/pixelpass --silent 2>/dev/null)
    fi

    if [ -d "$PIXELPASS_DIR/node_modules/@injistack/pixelpass" ]; then
        QR_DATA_FILE="${OUTPUT_FILE%.json}-qr.txt"
        QR_PNG_FILE="${OUTPUT_FILE%.json}-qr.png"

        # Encode with PixelPass
        (cd "$PIXELPASS_DIR" && node -e "
const { generateQRData } = require('@injistack/pixelpass');
const fs = require('fs');
const credential = JSON.parse(fs.readFileSync('$OUTPUT_FILE', 'utf8'));
process.stdout.write(generateQRData(JSON.stringify(credential)));
") > "$QR_DATA_FILE" 2>/dev/null

        if [ -s "$QR_DATA_FILE" ]; then
            echo -e "${GREEN}[OK] Credential encoded with PixelPass${NC}"
            echo "QR data saved to: $QR_DATA_FILE"

            # Generate PNG if qrencode is available
            if command -v qrencode &> /dev/null; then
                qrencode -o "$QR_PNG_FILE" -s 10 -m 2 < "$QR_DATA_FILE"
                echo -e "${GREEN}[OK] QR code image saved to: $QR_PNG_FILE${NC}"

                # Display ASCII QR in terminal
                echo ""
                echo "Scan with Inji Verify:"
                echo ""
                qrencode -t ANSIUTF8 < "$QR_DATA_FILE"
            else
                echo -e "${YELLOW}[WARN] qrencode not installed - install with: sudo apt install qrencode${NC}"
            fi
        else
            echo -e "${RED}[FAIL] PixelPass encoding failed${NC}"
        fi
    else
        echo -e "${RED}[FAIL] Could not install PixelPass${NC}"
    fi
fi

# ============================================================================
# SUMMARY
# ============================================================================

echo ""
echo -e "${BLUE}==========================================="
echo "  Summary"
echo -e "===========================================${NC}"
echo ""
echo "Mode: $MODE"
echo "Credential File: $OUTPUT_FILE"
[ "$GENERATE_QR" = true ] && [ -f "${OUTPUT_FILE%.json}-qr.png" ] && echo "QR Image: ${OUTPUT_FILE%.json}-qr.png"
echo ""

# Extract issuer for reference
ISSUER=$(echo "$CREDENTIAL" | grep -o '"issuer"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
echo "Issuer DID: $ISSUER"
echo ""
echo -e "${YELLOW}Note: Mock credentials have invalid signatures."
echo "      They test adapter routing but will fail cryptographic verification."
echo "      Use --mode issue with a real did:indy DID for full verification.${NC}"
echo ""
