#!/bin/bash
#
# CREDEBL Credential Monitor
# Monitors the state of a credential exchange until completion
#
# Usage: ./monitor-credential.sh <credential_record_id> [base_url] [api_key]
#
# Arguments:
#   credential_record_id - The ID of the credential exchange record
#   base_url            - Agent admin URL (default: http://localhost:8004)
#   api_key             - Agent API key (default: from CREDEBL_API_KEY env var)
#

set -e

# Configuration
CREDENTIAL_ID="${1:-}"
BASE_URL="${2:-http://localhost:8004}"
API_KEY="${3:-${CREDEBL_API_KEY:-}}"
POLL_INTERVAL=3
MAX_WAIT=300  # 5 minutes

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Validate inputs
if [ -z "$CREDENTIAL_ID" ]; then
    echo -e "${RED}Error: credential_record_id is required${NC}"
    echo ""
    echo "Usage: $0 <credential_record_id> [base_url] [api_key]"
    echo ""
    echo "Examples:"
    echo "  $0 abc123-def456-ghi789"
    echo "  $0 abc123-def456-ghi789 http://localhost:8004 myapikey"
    echo ""
    echo "You can also set CREDEBL_API_KEY environment variable"
    exit 1
fi

if [ -z "$API_KEY" ]; then
    echo -e "${RED}Error: API key is required${NC}"
    echo "Set CREDEBL_API_KEY environment variable or pass as third argument"
    exit 1
fi

# State icons and descriptions
get_state_display() {
    local state="$1"
    case "$state" in
        "offer-sent")
            echo -e "${YELLOW}⏳${NC} offer-sent        - Waiting for holder to accept"
            ;;
        "proposal-received")
            echo -e "${CYAN}📥${NC} proposal-received - Holder sent proposal"
            ;;
        "request-received")
            echo -e "${BLUE}📨${NC} request-received  - Processing credential request"
            ;;
        "credential-issued")
            echo -e "${GREEN}✅${NC} credential-issued - Credential sent to holder"
            ;;
        "done")
            echo -e "${GREEN}🎉${NC} done              - Exchange completed!"
            ;;
        *)
            echo -e "${YELLOW}❓${NC} $state"
            ;;
    esac
}

# Function to get credential state
get_credential() {
    curl -s -H "authorization: $API_KEY" \
        "${BASE_URL}/didcomm/credentials/${CREDENTIAL_ID}" 2>/dev/null
}

# Header
echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          CREDEBL Credential Exchange Monitor               ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}Credential ID:${NC} $CREDENTIAL_ID"
echo -e "  ${CYAN}Base URL:${NC}      $BASE_URL"
echo -e "  ${CYAN}Poll Interval:${NC} ${POLL_INTERVAL}s"
echo ""
echo -e "${YELLOW}Monitoring... Press Ctrl+C to stop${NC}"
echo ""
echo "─────────────────────────────────────────────────────────────"

# Initial check
RESPONSE=$(get_credential)
if [ -z "$RESPONSE" ] || echo "$RESPONSE" | grep -q "Cannot GET"; then
    echo -e "${RED}Error: Could not retrieve credential record${NC}"
    echo "Response: $RESPONSE"
    exit 1
fi

# Parse initial state
CURRENT_STATE=$(echo "$RESPONSE" | jq -r '.state // "unknown"')
LAST_STATE=""
START_TIME=$(date +%s)
ELAPSED=0

echo ""
echo -e "$(date '+%H:%M:%S') | Initial State:"
get_state_display "$CURRENT_STATE"
echo ""

# Monitor loop
while true; do
    RESPONSE=$(get_credential)

    if [ -z "$RESPONSE" ]; then
        echo -e "${RED}$(date '+%H:%M:%S') | Error fetching credential${NC}"
        sleep $POLL_INTERVAL
        continue
    fi

    CURRENT_STATE=$(echo "$RESPONSE" | jq -r '.state // "unknown"')
    UPDATED_AT=$(echo "$RESPONSE" | jq -r '.updatedAt // "N/A"')

    # Check if state changed
    if [ "$CURRENT_STATE" != "$LAST_STATE" ]; then
        echo -e "$(date '+%H:%M:%S') | State changed:"
        get_state_display "$CURRENT_STATE"
        echo -e "             Updated: $UPDATED_AT"
        echo ""
        LAST_STATE="$CURRENT_STATE"
    fi

    # Check for completion
    if [ "$CURRENT_STATE" = "done" ] || [ "$CURRENT_STATE" = "credential-issued" ]; then
        echo "─────────────────────────────────────────────────────────────"
        echo ""
        echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║           CREDENTIAL ISSUED SUCCESSFULLY!                  ║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo "The credential should now be in the holder's wallet."
        echo ""

        # Get and display credential details
        FORM_DATA=$(curl -s -H "authorization: $API_KEY" \
            "${BASE_URL}/didcomm/credentials/${CREDENTIAL_ID}/form-data" 2>/dev/null)

        if echo "$FORM_DATA" | jq -e '.credential.jsonld' > /dev/null 2>&1; then
            echo -e "${CYAN}Issued Credential:${NC}"
            echo "$FORM_DATA" | jq '.credential.jsonld'
            echo ""
        fi

        ELAPSED=$(($(date +%s) - START_TIME))
        echo -e "Total time: ${ELAPSED}s"
        exit 0
    fi

    # Check for timeout
    ELAPSED=$(($(date +%s) - START_TIME))
    if [ $ELAPSED -gt $MAX_WAIT ]; then
        echo ""
        echo -e "${RED}Timeout after ${MAX_WAIT}s${NC}"
        echo "Current state: $CURRENT_STATE"
        echo ""
        echo "If stuck at 'request-received', check agent logs:"
        echo "  docker logs YOUR_CONTAINER_NAME 2>&1 | tail -50"
        exit 1
    fi

    # Show waiting indicator
    printf "\r$(date '+%H:%M:%S') | Waiting... (${ELAPSED}s elapsed, state: $CURRENT_STATE)  "

    sleep $POLL_INTERVAL
done
