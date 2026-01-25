#!/bin/bash
# verify-sample-credentials.sh - Test sample credentials through the verification adapter
#
# This script verifies all sample credentials in the sample-credentials directory
# through the adapter to test routing logic for different DID methods.
#
# Usage: ./verify-sample-credentials.sh [OPTIONS]
#   -a, --adapter-port PORT   Adapter port (default: 8085)
#   -d, --directory DIR       Directory containing credentials (default: ./sample-credentials)
#   -f, --file FILE           Verify a single credential file
#   -h, --help                Show this help message

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
ADAPTER_PORT="8085"
CRED_DIR="$SCRIPT_DIR/sample-credentials"
SINGLE_FILE=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -a|--adapter-port)
            ADAPTER_PORT="$2"
            shift 2
            ;;
        -d|--directory)
            CRED_DIR="$2"
            shift 2
            ;;
        -f|--file)
            SINGLE_FILE="$2"
            shift 2
            ;;
        -h|--help)
            head -15 "$0" | tail -12
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
echo "  Sample Credential Verification Test"
echo -e "===========================================${NC}"
echo ""

# Check adapter health
echo -e "${CYAN}Checking adapter health...${NC}"
HEALTH=$(curl -s "http://localhost:$ADAPTER_PORT/health" 2>/dev/null)

if [ -z "$HEALTH" ]; then
    echo -e "${RED}ERROR: Adapter not reachable on port $ADAPTER_PORT${NC}"
    echo ""
    echo "Start the adapter with:"
    echo "  cd $SCRIPT_DIR/adapter && node offline-adapter.js"
    exit 1
fi

CONNECTIVITY=$(echo "$HEALTH" | grep -o '"connectivity":"[^"]*"' | cut -d'"' -f4)
CACHED_ISSUERS=$(echo "$HEALTH" | grep -o '"totalIssuers":[0-9]*' | cut -d':' -f2)
echo -e "${GREEN}Adapter Status: $CONNECTIVITY, Cached Issuers: ${CACHED_ISSUERS:-0}${NC}"
echo ""

# Function to verify a single credential
verify_credential() {
    local file="$1"
    local filename=$(basename "$file")

    # Extract credential info
    local issuer=$(grep -o '"issuer"[[:space:]]*:[[:space:]]*"[^"]*"' "$file" | head -1 | cut -d'"' -f4)
    local proof_type=$(grep -o '"type"[[:space:]]*:[[:space:]]*"[^"]*Signature[^"]*"' "$file" | head -1 | cut -d'"' -f4)
    local did_method=$(echo "$issuer" | cut -d':' -f1-2)

    echo -e "${CYAN}─────────────────────────────────────────${NC}"
    echo -e "${BLUE}File:${NC} $filename"
    echo -e "${BLUE}Issuer:${NC} $issuer"
    echo -e "${BLUE}DID Method:${NC} $did_method"
    echo -e "${BLUE}Proof Type:${NC} ${proof_type:-Unknown}"
    echo ""

    # Submit for verification
    local response=$(curl -s -X POST "http://localhost:$ADAPTER_PORT/v1/verify/vc-verification" \
        -H "Content-Type: application/json" \
        -d "{\"verifiableCredentials\": [$(cat "$file")]}" 2>/dev/null)

    # Parse response
    local status=$(echo "$response" | grep -o '"verificationStatus":"[^"]*"' | cut -d'"' -f4)
    local backend=$(echo "$response" | grep -o '"backend":"[^"]*"' | cut -d'"' -f4)
    local offline=$(echo "$response" | grep -o '"offline":[^,}]*' | cut -d':' -f2)
    local error=$(echo "$response" | grep -o '"error":"[^"]*"' | cut -d'"' -f4)
    local message=$(echo "$response" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)

    # Display result
    case "$status" in
        SUCCESS)
            echo -e "Result: ${GREEN}SUCCESS${NC}"
            ;;
        INVALID)
            echo -e "Result: ${RED}INVALID${NC}"
            [ -n "$error" ] && echo -e "Error: $error"
            ;;
        UNKNOWN_ISSUER)
            echo -e "Result: ${YELLOW}UNKNOWN_ISSUER${NC}"
            echo "Note: Issuer not in cache (expected for mock credentials)"
            ;;
        ERROR)
            echo -e "Result: ${RED}ERROR${NC}"
            [ -n "$error" ] && echo -e "Error: $error"
            ;;
        *)
            echo -e "Result: ${YELLOW}$status${NC}"
            ;;
    esac

    [ -n "$backend" ] && echo "Backend: $backend"
    [ -n "$offline" ] && echo "Offline: $offline"
    [ -n "$message" ] && echo "Message: $message"
    echo ""
}

# Verify credentials
if [ -n "$SINGLE_FILE" ]; then
    # Single file mode
    if [ -f "$SINGLE_FILE" ]; then
        verify_credential "$SINGLE_FILE"
    else
        echo -e "${RED}ERROR: File not found: $SINGLE_FILE${NC}"
        exit 1
    fi
else
    # Directory mode
    if [ ! -d "$CRED_DIR" ]; then
        echo -e "${RED}ERROR: Directory not found: $CRED_DIR${NC}"
        exit 1
    fi

    # Find all JSON files (excluding README)
    credentials=$(find "$CRED_DIR" -name "*.json" -type f | sort)
    count=$(echo "$credentials" | grep -c . || echo 0)

    if [ "$count" -eq 0 ]; then
        echo -e "${YELLOW}No credential files found in $CRED_DIR${NC}"
        exit 0
    fi

    echo -e "Found ${BLUE}$count${NC} credential file(s) in $CRED_DIR"
    echo ""

    # Verify each credential
    for cred in $credentials; do
        verify_credential "$cred"
    done
fi

echo -e "${CYAN}─────────────────────────────────────────${NC}"
echo ""
echo -e "${BLUE}Summary:${NC}"
echo "- Mock credentials will show UNKNOWN_ISSUER or INVALID (expected)"
echo "- did:indy credentials route to CREDEBL Agent"
echo "- did:polygon credentials route to CREDEBL Agent"
echo "- did:web/did:key credentials route to Inji Verify Service"
echo ""
echo -e "${YELLOW}To test with valid credentials:${NC}"
echo "1. Issue a real credential using test-indy-credential.sh --mode issue"
echo "2. Or sync a known issuer: curl -X POST localhost:$ADAPTER_PORT/sync -d '{\"did\":\"...\"}'"
echo ""
