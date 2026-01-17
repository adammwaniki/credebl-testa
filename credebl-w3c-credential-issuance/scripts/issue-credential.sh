#!/bin/bash
#
# CREDEBL W3C Credential Issuance Script
# Issues a W3C JSON-LD Verifiable Credential to a connected holder
#
# Usage: ./issue-credential.sh <connection_id> [options]
#
# Options:
#   -t, --type        Credential type (default: EmploymentCredential)
#   -n, --name        Organization/issuer name
#   -p, --position    Job position (for employment credentials)
#   -b, --base-url    Agent admin URL (default: http://localhost:8004)
#   -k, --api-key     Agent API key (or set CREDEBL_API_KEY env var)
#   -m, --monitor     Monitor credential state until completion
#   -h, --help        Show this help message
#

set -e

# Default configuration
BASE_URL="${CREDEBL_BASE_URL:-http://localhost:8004}"
API_KEY="${CREDEBL_API_KEY:-}"
CREDENTIAL_TYPE="EmploymentCredential"
ORG_NAME="CREDEBL Issuer"
POSITION="Software Engineer"
MONITOR=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

show_help() {
    cat << EOF
CREDEBL W3C Credential Issuance Script

Usage: $0 <connection_id> [options]

Arguments:
  connection_id    The ID of the DIDComm connection with the holder

Options:
  -t, --type       Credential type (default: EmploymentCredential)
  -n, --name       Organization/issuer name (default: CREDEBL Issuer)
  -p, --position   Job position for employment credentials (default: Software Engineer)
  -b, --base-url   Agent admin URL (default: http://localhost:8004)
  -k, --api-key    Agent API key (or set CREDEBL_API_KEY env var)
  -m, --monitor    Monitor credential state until completion
  -h, --help       Show this help message

Environment Variables:
  CREDEBL_API_KEY    Agent API key
  CREDEBL_BASE_URL   Agent admin URL

Examples:
  # Basic usage
  $0 abc123-connection-id -k myapikey

  # With monitoring
  $0 abc123-connection-id -k myapikey -m

  # Custom credential
  $0 abc123-connection-id -k myapikey -t MembershipCredential -n "Tech Association"

EOF
    exit 0
}

# Parse arguments
CONNECTION_ID=""
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--type)
            CREDENTIAL_TYPE="$2"
            shift 2
            ;;
        -n|--name)
            ORG_NAME="$2"
            shift 2
            ;;
        -p|--position)
            POSITION="$2"
            shift 2
            ;;
        -b|--base-url)
            BASE_URL="$2"
            shift 2
            ;;
        -k|--api-key)
            API_KEY="$2"
            shift 2
            ;;
        -m|--monitor)
            MONITOR=true
            shift
            ;;
        -h|--help)
            show_help
            ;;
        -*)
            echo -e "${RED}Unknown option: $1${NC}"
            show_help
            ;;
        *)
            if [ -z "$CONNECTION_ID" ]; then
                CONNECTION_ID="$1"
            fi
            shift
            ;;
    esac
done

# Validate required inputs
if [ -z "$CONNECTION_ID" ]; then
    echo -e "${RED}Error: connection_id is required${NC}"
    echo ""
    show_help
fi

if [ -z "$API_KEY" ]; then
    echo -e "${RED}Error: API key is required${NC}"
    echo "Set CREDEBL_API_KEY environment variable or use -k option"
    exit 1
fi

# Check if jq is available
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is required but not installed${NC}"
    echo "Install with: apt-get install jq (or brew install jq)"
    exit 1
fi

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║        CREDEBL W3C Credential Issuance                     ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Get issuer DID
echo -e "${YELLOW}Fetching issuer DID...${NC}"
DIDS_RESPONSE=$(curl -s -H "authorization: $API_KEY" "${BASE_URL}/dids")

ISSUER_DID=$(echo "$DIDS_RESPONSE" | jq -r '.[0].did // empty')
if [ -z "$ISSUER_DID" ]; then
    echo -e "${RED}Error: Could not retrieve issuer DID${NC}"
    echo "Response: $DIDS_RESPONSE"
    exit 1
fi
echo -e "  Issuer DID: ${GREEN}$ISSUER_DID${NC}"

# Get connection details to find holder DID
echo -e "${YELLOW}Fetching connection details...${NC}"
CONN_RESPONSE=$(curl -s -H "authorization: $API_KEY" "${BASE_URL}/didcomm/connections/${CONNECTION_ID}")

CONN_STATE=$(echo "$CONN_RESPONSE" | jq -r '.state // empty')
if [ "$CONN_STATE" != "completed" ]; then
    echo -e "${RED}Error: Connection is not in 'completed' state${NC}"
    echo "Current state: $CONN_STATE"
    echo "Please ensure the connection is established before issuing credentials"
    exit 1
fi

HOLDER_DID=$(echo "$CONN_RESPONSE" | jq -r '.theirDid // empty')
if [ -z "$HOLDER_DID" ]; then
    echo -e "${YELLOW}Warning: Could not get holder DID from connection${NC}"
    HOLDER_DID="did:key:placeholder"
fi
echo -e "  Holder DID: ${GREEN}$HOLDER_DID${NC}"
echo -e "  Connection State: ${GREEN}$CONN_STATE${NC}"

# Generate issuance date
ISSUANCE_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Build credential payload
echo ""
echo -e "${YELLOW}Building credential payload...${NC}"
echo -e "  Type: $CREDENTIAL_TYPE"
echo -e "  Organization: $ORG_NAME"
echo -e "  Position: $POSITION"
echo -e "  Issuance Date: $ISSUANCE_DATE"

PAYLOAD=$(cat << EOF
{
  "connectionId": "$CONNECTION_ID",
  "protocolVersion": "v2",
  "credentialFormats": {
    "jsonld": {
      "credential": {
        "@context": [
          "https://www.w3.org/2018/credentials/v1",
          "https://www.w3.org/2018/credentials/examples/v1"
        ],
        "type": ["VerifiableCredential", "$CREDENTIAL_TYPE"],
        "issuer": "$ISSUER_DID",
        "issuanceDate": "$ISSUANCE_DATE",
        "credentialSubject": {
          "id": "$HOLDER_DID",
          "employeeOf": {
            "name": "$ORG_NAME",
            "position": "$POSITION",
            "startDate": "2024-01-01"
          }
        }
      },
      "options": {
        "proofType": "Ed25519Signature2018",
        "proofPurpose": "assertionMethod"
      }
    }
  },
  "autoAcceptCredential": "always"
}
EOF
)

# Issue credential
echo ""
echo -e "${YELLOW}Issuing credential...${NC}"

RESPONSE=$(curl -s -X POST \
    -H "authorization: $API_KEY" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "${BASE_URL}/didcomm/credentials/create-offer")

# Check for errors
if echo "$RESPONSE" | jq -e '.message' > /dev/null 2>&1; then
    ERROR_MSG=$(echo "$RESPONSE" | jq -r '.message')
    echo -e "${RED}Error: $ERROR_MSG${NC}"
    exit 1
fi

CREDENTIAL_ID=$(echo "$RESPONSE" | jq -r '.id')
STATE=$(echo "$RESPONSE" | jq -r '.state')
THREAD_ID=$(echo "$RESPONSE" | jq -r '.threadId')

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           Credential Offer Sent Successfully!              ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Credential ID: ${BLUE}$CREDENTIAL_ID${NC}"
echo -e "  Thread ID:     $THREAD_ID"
echo -e "  State:         $STATE"
echo ""

if [ "$MONITOR" = true ]; then
    echo -e "${YELLOW}Monitoring credential state...${NC}"
    echo -e "Please accept the credential offer in your mobile wallet"
    echo ""

    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$SCRIPT_DIR/monitor-credential.sh" ]; then
        "$SCRIPT_DIR/monitor-credential.sh" "$CREDENTIAL_ID" "$BASE_URL" "$API_KEY"
    else
        # Inline monitoring
        while true; do
            CRED_STATE=$(curl -s -H "authorization: $API_KEY" \
                "${BASE_URL}/didcomm/credentials/${CREDENTIAL_ID}" | jq -r '.state')

            echo "$(date '+%H:%M:%S') | State: $CRED_STATE"

            if [ "$CRED_STATE" = "done" ] || [ "$CRED_STATE" = "credential-issued" ]; then
                echo ""
                echo -e "${GREEN}Credential issued successfully!${NC}"
                break
            fi

            sleep 3
        done
    fi
else
    echo "To monitor the credential state, run:"
    echo "  ./monitor-credential.sh $CREDENTIAL_ID $BASE_URL $API_KEY"
    echo ""
    echo "Or accept the credential in your wallet and check manually:"
    echo "  curl -H 'authorization: $API_KEY' '${BASE_URL}/didcomm/credentials/${CREDENTIAL_ID}' | jq .state"
fi
