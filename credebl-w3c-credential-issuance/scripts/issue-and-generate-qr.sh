#!/bin/bash
#
# issue-and-generate-qr.sh
#
# Issues a W3C JSON-LD Verifiable Credential and generates a PixelPass-encoded
# QR code compatible with Inji Verify.
#
# Usage: ./issue-and-generate-qr.sh <connection_id> [options]
#
# Options:
#   --api-key KEY       API key for agent authentication (default: from env or prompt)
#   --agent-url URL     Agent admin URL (default: http://localhost:8003)
#   --issuer-did DID    Issuer DID (default: fetched from agent)
#   --output-dir DIR    Output directory for QR code (default: current directory)
#   --credential-type   Credential type (default: EmploymentCredential)
#   --help              Show this help message
#

set -e

# Default configuration
AGENT_URL="${AGENT_URL:-http://localhost:8003}"
API_KEY="${API_KEY:-}"
OUTPUT_DIR="."
CREDENTIAL_TYPE="EmploymentCredential"
ISSUER_DID=""
CONNECTION_ID=""
# Example for Employment Data
EMPLOYER_NAME="Testa Credebl Farms"
JOB_TITLE="Field Service Engineer"
START_DATE="2026-01-01"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_error() { echo -e "${RED}ERROR: $1${NC}" >&2; }
print_success() { echo -e "${GREEN}$1${NC}"; }
print_warning() { echo -e "${YELLOW}$1${NC}"; }
print_info() { echo -e "$1"; }

show_help() {
    head -25 "$0" | tail -20
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --api-key)
            API_KEY="$2"
            shift 2
            ;;
        --agent-url)
            AGENT_URL="$2"
            shift 2
            ;;
        --issuer-did)
            ISSUER_DID="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --credential-type)
            CREDENTIAL_TYPE="$2"
            shift 2
            ;;
        --help|-h)
            show_help
            ;;
        *)
            if [[ -z "$CONNECTION_ID" ]]; then
                CONNECTION_ID="$1"
            fi
            shift
            ;;
    esac
done

# Validate required parameters
if [[ -z "$CONNECTION_ID" ]]; then
    print_error "Connection ID is required"
    echo "Usage: $0 <connection_id> [options]"
    exit 1
fi

if [[ -z "$API_KEY" ]]; then
    read -p "Enter API Key: " API_KEY
fi

# Check dependencies
check_dependencies() {
    local missing=()

    command -v curl &>/dev/null || missing+=("curl")
    command -v jq &>/dev/null || missing+=("jq")
    command -v node &>/dev/null || missing+=("node")
    command -v qrencode &>/dev/null || missing+=("qrencode")

    if [[ ${#missing[@]} -gt 0 ]]; then
        print_error "Missing dependencies: ${missing[*]}"
        exit 1
    fi

    # Check for pixelpass
    if ! node -e "require('@injistack/pixelpass')" 2>/dev/null; then
        print_warning "Installing @injistack/pixelpass..."
        npm install @injistack/pixelpass --silent
    fi
}

# Get JWT token
get_token() {
    print_info "Getting authentication token..."
    JWT=$(curl -s -X POST "$AGENT_URL/agent/token" \
        -H "authorization: $API_KEY" | jq -r '.token')

    if [[ -z "$JWT" || "$JWT" == "null" ]]; then
        print_error "Failed to get authentication token"
        exit 1
    fi

    print_success "Token obtained"
}

# Get issuer DID if not provided
get_issuer_did() {
    if [[ -z "$ISSUER_DID" ]]; then
        print_info "Fetching issuer DID..."
        ISSUER_DID=$(curl -s -H "authorization: $JWT" "$AGENT_URL/dids" \
            | jq -r '.[0].did')

        if [[ -z "$ISSUER_DID" || "$ISSUER_DID" == "null" ]]; then
            print_error "Failed to get issuer DID"
            exit 1
        fi
    fi
    print_info "Issuer DID: $ISSUER_DID"
}

# Get holder DID from connection
get_holder_did() {
    print_info "Fetching holder DID from connection..."
    HOLDER_DID=$(curl -s -H "authorization: $JWT" \
        "$AGENT_URL/didcomm/connections/$CONNECTION_ID" \
        | jq -r '.theirDid')

    if [[ -z "$HOLDER_DID" || "$HOLDER_DID" == "null" ]]; then
        print_warning "Could not get holder DID, using placeholder"
        HOLDER_DID="did:example:holder"
    fi
    print_info "Holder DID: $HOLDER_DID"
}

# Issue credential
issue_credential() {
    print_info "Issuing credential..."

    ISSUANCE_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    RESPONSE=$(curl -s -X POST "$AGENT_URL/didcomm/credentials/create-offer" \
        -H "authorization: $JWT" \
        -H "Content-Type: application/json" \
        -d "{
            \"connectionId\": \"$CONNECTION_ID\",
            \"protocolVersion\": \"v2\",
            \"credentialFormats\": {
                \"jsonld\": {
                    \"credential\": {
                        \"@context\": [
                            \"https://www.w3.org/2018/credentials/v1\",
                            \"https://www.w3.org/2018/credentials/examples/v1\"
                        ],
                        \"type\": [\"VerifiableCredential\", \"$CREDENTIAL_TYPE\"],
                        \"issuer\": \"$ISSUER_DID\",
                        \"issuanceDate\": \"$ISSUANCE_DATE\",
                        \"credentialSubject\": {
                            \"id\": \"$HOLDER_DID\",
                            \"employeeOf\": {
                                \"name\": \"$EMPLOYER_NAME\",
                                \"position\": \"$JOB_TITLE\",
                                \"startDate\": \"$START_DATE\"
                            }
                        }
                    },
                    \"options\": {
                        \"proofType\": \"Ed25519Signature2018\",
                        \"proofPurpose\": \"assertionMethod\"
                    }
                }
            },
            \"autoAcceptCredential\": \"always\"
        }")

    CREDENTIAL_RECORD_ID=$(echo "$RESPONSE" | jq -r '.id')

    if [[ -z "$CREDENTIAL_RECORD_ID" || "$CREDENTIAL_RECORD_ID" == "null" ]]; then
        print_error "Failed to issue credential"
        echo "$RESPONSE" | jq .
        exit 1
    fi

    print_success "Credential offer sent: $CREDENTIAL_RECORD_ID"
}

# Wait for credential exchange to complete
wait_for_completion() {
    print_info "Waiting for credential exchange to complete..."

    local max_attempts=30
    local attempt=0

    while [[ $attempt -lt $max_attempts ]]; do
        STATE=$(curl -s -H "authorization: $JWT" \
            "$AGENT_URL/didcomm/credentials/$CREDENTIAL_RECORD_ID" \
            | jq -r '.state')

        case "$STATE" in
            "done")
                print_success "Credential exchange completed!"
                return 0
                ;;
            "abandoned"|"declined")
                print_error "Credential exchange failed: $STATE"
                exit 1
                ;;
            *)
                echo -n "."
                sleep 2
                ((attempt++))
                ;;
        esac
    done

    print_warning "\nTimeout waiting for completion. Current state: $STATE"
    print_info "You may need to accept the credential in the holder wallet."
}

# Retrieve signed credential
get_signed_credential() {
    print_info "Retrieving signed credential..."

    CREDENTIAL_FILE="$OUTPUT_DIR/credential-$CREDENTIAL_RECORD_ID.json"

    curl -s -H "authorization: $JWT" \
        "$AGENT_URL/didcomm/credentials/$CREDENTIAL_RECORD_ID/form-data" \
        | jq '.credential.jsonld' > "$CREDENTIAL_FILE"

    if [[ ! -s "$CREDENTIAL_FILE" ]]; then
        print_error "Failed to retrieve signed credential"
        exit 1
    fi

    print_success "Credential saved to: $CREDENTIAL_FILE"
}

# Encode with PixelPass and generate QR
generate_qr_code() {
    print_info "Encoding credential with PixelPass..."

    QRDATA_FILE="$OUTPUT_DIR/qrdata-$CREDENTIAL_RECORD_ID.txt"
    PNG_FILE="$OUTPUT_DIR/credential-qr-$CREDENTIAL_RECORD_ID.png"

    node -e "
const { generateQRData } = require('@injistack/pixelpass');
const fs = require('fs');
const credential = JSON.parse(fs.readFileSync('$CREDENTIAL_FILE', 'utf8'));
process.stdout.write(generateQRData(JSON.stringify(credential)));
" > "$QRDATA_FILE"

    if [[ ! -s "$QRDATA_FILE" ]]; then
        print_error "Failed to encode credential with PixelPass"
        exit 1
    fi

    print_info "Generating QR code..."
    qrencode -o "$PNG_FILE" -s 10 -m 2 < "$QRDATA_FILE"

    print_success "QR code saved to: $PNG_FILE"

    # Also show in terminal
    print_info "\nQR Code (scan with Inji Verify):"
    qrencode -t ANSIUTF8 < "$QRDATA_FILE"
}

# Main execution
main() {
    print_info "============================================"
    print_info "  Credential Issuance & QR Code Generator"
    print_info "============================================"
    print_info ""

    check_dependencies
    get_token
    get_issuer_did
    get_holder_did
    issue_credential
    wait_for_completion
    get_signed_credential
    generate_qr_code

    print_info ""
    print_success "============================================"
    print_success "  Process Complete!"
    print_success "============================================"
    print_info ""
    print_info "Files generated:"
    print_info "  - Credential: $CREDENTIAL_FILE"
    print_info "  - QR Data: $QRDATA_FILE"
    print_info "  - QR Image: $PNG_FILE"
    print_info ""
    print_info "Scan the QR code with Inji Verify to verify the credential."
}

main
