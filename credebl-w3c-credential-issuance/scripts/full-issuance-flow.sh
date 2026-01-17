#!/bin/bash
#
# CREDEBL Full W3C Credential Issuance Flow
# Complete end-to-end script for establishing connection and issuing credentials
#
# Usage: ./full-issuance-flow.sh [options]
#
# This script will:
# 1. Check agent health
# 2. Create an OOB invitation
# 3. Generate and display QR code
# 4. Wait for connection establishment
# 5. Issue a W3C credential
# 6. Monitor until completion
#

set -e

# Default configuration
BASE_URL="${CREDEBL_BASE_URL:-http://localhost:8004}"
API_KEY="${CREDEBL_API_KEY:-}"
ORG_NAME="Testa Credebl Farms"
CREDENTIAL_TYPE="EmploymentCredential"
POSITION="Field Service Engineer"
START_WORK_DATE="2026-01-01"
QR_OUTPUT="/tmp/credebl_invitation_qr.png"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

show_help() {
    cat << EOF
CREDEBL Full W3C Credential Issuance Flow

This script performs the complete credential issuance workflow:
  1. Verifies agent is healthy
  2. Creates an OOB invitation
  3. Generates a QR code
  4. Waits for connection establishment
  5. Issues a W3C credential
  6. Monitors until completion

Usage: $0 [options]

Options:
  -b, --base-url   Agent admin URL (default: http://localhost:8004)
  -k, --api-key    Agent API key (required, or set CREDEBL_API_KEY)
  -n, --name       Organization name (default: CREDEBL Issuer)
  -t, --type       Credential type (default: EmploymentCredential)
  -p, --position   Job position (default: Software Engineer)
  -q, --qr-output  QR code output file (default: /tmp/credebl_invitation_qr.png)
  -h, --help       Show this help

Environment Variables:
  CREDEBL_API_KEY    Agent API key
  CREDEBL_BASE_URL   Agent admin URL

Example:
  export CREDEBL_API_KEY="supersecret-that-too-16chars"
  $0 -n "Acme Corporation" -p "Senior Engineer"

EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -b|--base-url) BASE_URL="$2"; shift 2 ;;
        -k|--api-key) API_KEY="$2"; shift 2 ;;
        -n|--name) ORG_NAME="$2"; shift 2 ;;
        -t|--type) CREDENTIAL_TYPE="$2"; shift 2 ;;
        -p|--position) POSITION="$2"; shift 2 ;;
        -q|--qr-output) QR_OUTPUT="$2"; shift 2 ;;
        -h|--help) show_help ;;
        *) echo -e "${RED}Unknown option: $1${NC}"; show_help ;;
    esac
done

# Validate inputs
if [ -z "$API_KEY" ]; then
    echo -e "${RED}Error: API key is required${NC}"
    echo "Set CREDEBL_API_KEY environment variable or use -k option"
    exit 1
fi

# Check dependencies
check_dependency() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${RED}Error: $1 is required but not installed${NC}"
        exit 1
    fi
}

check_dependency curl
check_dependency jq

# Check optional dependencies for QR generation
if ! command -v qrencode &> /dev/null; then
    echo -e "${YELLOW}Warning: qrencode not installed - QR code generation will be limited${NC}"
    echo -e "  Install with: sudo apt install qrencode"
    echo ""
fi

# Header
clear
echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║        CREDEBL W3C Credential Issuance - Full Flow             ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}Base URL:${NC}        $BASE_URL"
echo -e "  ${CYAN}Organization:${NC}    $ORG_NAME"
echo -e "  ${CYAN}Credential Type:${NC} $CREDENTIAL_TYPE"
echo ""

# Step 1: Health Check
echo -e "${YELLOW}━━━ Step 1: Checking Agent Health ━━━${NC}"
AGENT_INFO=$(curl -s -H "authorization: $API_KEY" "${BASE_URL}/agent" 2>/dev/null)

if echo "$AGENT_INFO" | jq -e '.isInitialized == true' > /dev/null 2>&1; then
    AGENT_LABEL=$(echo "$AGENT_INFO" | jq -r '.label')
    AGENT_ENDPOINT=$(echo "$AGENT_INFO" | jq -r '.endpoints[0]')
    echo -e "  ${GREEN}✓${NC} Agent is healthy"
    echo -e "    Label: $AGENT_LABEL"
    echo -e "    Endpoint: $AGENT_ENDPOINT"
else
    echo -e "  ${RED}✗${NC} Agent health check failed"
    echo "    Response: $AGENT_INFO"
    exit 1
fi
echo ""

# Step 2: Get Issuer DID
echo -e "${YELLOW}━━━ Step 2: Fetching Issuer DID ━━━${NC}"
DIDS=$(curl -s -H "authorization: $API_KEY" "${BASE_URL}/dids")
# IMPORTANT: Filter for did:key only - did:peer DIDs are connection-specific and cannot sign credentials
ISSUER_DID=$(echo "$DIDS" | jq -r '[.[] | select(.did | startswith("did:key"))][0].did // empty')

if [ -n "$ISSUER_DID" ]; then
    echo -e "  ${GREEN}✓${NC} Issuer DID: $ISSUER_DID"
else
    echo -e "  ${RED}✗${NC} No did:key DID found. Create one first."
    echo "    Available DIDs:"
    echo "$DIDS" | jq -r '.[].did'
    exit 1
fi
echo ""

# Step 3: Create OOB Invitation
echo -e "${YELLOW}━━━ Step 3: Creating OOB Invitation ━━━${NC}"

# SECURITY FIX: Record timestamp BEFORE creating invitation
# This ensures we only accept NEW connections created after this point
INVITATION_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo -e "  ${CYAN}Timestamp:${NC} $INVITATION_TIMESTAMP"

INVITATION_PAYLOAD=$(cat << EOF
{
  "label": "$ORG_NAME",
  "goalCode": "issue-vc",
  "goal": "Issue Verifiable Credential",
  "handshake": true,
  "handshakeProtocols": [
    "https://didcomm.org/didexchange/1.x",
    "https://didcomm.org/connections/1.x"
  ],
  "autoAcceptConnection": true
}
EOF
)

INVITATION_RESPONSE=$(curl -s -X POST \
    -H "authorization: $API_KEY" \
    -H "Content-Type: application/json" \
    -d "$INVITATION_PAYLOAD" \
    "${BASE_URL}/didcomm/oob/create-invitation")

INVITATION_URL=$(echo "$INVITATION_RESPONSE" | jq -r '.invitationUrl // empty')
OOB_ID=$(echo "$INVITATION_RESPONSE" | jq -r '.outOfBandRecord.id // empty')

if [ -n "$INVITATION_URL" ]; then
    echo -e "  ${GREEN}✓${NC} Invitation created"
    echo -e "    OOB Record ID: $OOB_ID"
else
    echo -e "  ${RED}✗${NC} Failed to create invitation"
    echo "    Response: $INVITATION_RESPONSE"
    exit 1
fi
echo ""

# Step 4: Generate QR Code
echo -e "${YELLOW}━━━ Step 4: Generating QR Code ━━━${NC}"

# Try Python QR generation first
if command -v python3 &> /dev/null; then
    python3 << PYEOF
try:
    import qrcode
    qr = qrcode.QRCode(version=1, box_size=10, border=4)
    qr.add_data("$INVITATION_URL")
    qr.make(fit=True)
    img = qr.make_image(fill_color="black", back_color="white")
    img.save("$QR_OUTPUT")
    print("  ✓ QR code saved to: $QR_OUTPUT")
except ImportError:
    print("  ⚠ qrcode package not installed, using online generator")
    print("    Install with: pip install qrcode pillow")
except Exception as e:
    print(f"  ⚠ Error generating QR: {e}")
PYEOF
fi

# Display online QR generator link
ENCODED_URL=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$INVITATION_URL'))" 2>/dev/null || echo "$INVITATION_URL")
echo -e "  ${CYAN}Online QR Generator:${NC}"
echo -e "  https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=$ENCODED_URL"
echo ""

# Print ASCII QR if possible
if command -v python3 &> /dev/null; then
    python3 << 'PYEOF'
try:
    import qrcode
    qr = qrcode.QRCode(version=1, box_size=1, border=1)
    qr.add_data("""$INVITATION_URL""")
    qr.make(fit=True)
    print("\n  ASCII QR Code (scan with mobile wallet):\n")
    qr.print_ascii(invert=True)
except:
    pass
PYEOF
fi

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}  Please scan the QR code with your mobile wallet now${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Step 5: Wait for NEW Connection
echo -e "${YELLOW}━━━ Step 5: Waiting for NEW Connection ━━━${NC}"
echo -e "  ${CYAN}Only accepting connections created after:${NC} $INVITATION_TIMESTAMP"
echo "  Polling for new connection..."

CONNECTION_ID=""
MAX_WAIT=120
WAIT_TIME=0

while [ $WAIT_TIME -lt $MAX_WAIT ]; do
    CONNECTIONS=$(curl -s -H "authorization: $API_KEY" "${BASE_URL}/didcomm/connections")

    # SECURITY FIX: Only find connections created AFTER the invitation timestamp
    # This prevents reusing old connections and ensures the user must scan the new QR code
    CONNECTION_ID=$(echo "$CONNECTIONS" | jq -r --arg ts "$INVITATION_TIMESTAMP" '
        [.[] | select(.state == "completed" and .createdAt > $ts)] |
        sort_by(.createdAt) |
        reverse |
        .[0].id // empty
    ')

    if [ -n "$CONNECTION_ID" ]; then
        HOLDER_DID=$(echo "$CONNECTIONS" | jq -r ".[] | select(.id == \"$CONNECTION_ID\") | .theirDid // empty")
        CONN_CREATED=$(echo "$CONNECTIONS" | jq -r ".[] | select(.id == \"$CONNECTION_ID\") | .createdAt // empty")
        echo ""
        echo -e "  ${GREEN}✓${NC} NEW connection established!"
        echo -e "    Connection ID: $CONNECTION_ID"
        echo -e "    Holder DID: $HOLDER_DID"
        echo -e "    Created At: $CONN_CREATED"
        break
    fi

    printf "\r  Waiting for QR scan... (%ds / %ds)  " $WAIT_TIME $MAX_WAIT
    sleep 3
    WAIT_TIME=$((WAIT_TIME + 3))
done

if [ -z "$CONNECTION_ID" ]; then
    echo ""
    echo -e "  ${RED}✗${NC} Timeout waiting for NEW connection"
    echo -e "  ${YELLOW}Make sure you scanned the QR code with your wallet${NC}"
    exit 1
fi
echo ""

# Step 6: Issue Credential
echo -e "${YELLOW}━━━ Step 6: Issuing W3C Credential ━━━${NC}"

ISSUANCE_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

CREDENTIAL_PAYLOAD=$(cat << EOF
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
            "startDate": "$START_WORK_DATE"
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

CRED_RESPONSE=$(curl -s -X POST \
    -H "authorization: $API_KEY" \
    -H "Content-Type: application/json" \
    -d "$CREDENTIAL_PAYLOAD" \
    "${BASE_URL}/didcomm/credentials/create-offer")

CREDENTIAL_ID=$(echo "$CRED_RESPONSE" | jq -r '.id // empty')

if [ -n "$CREDENTIAL_ID" ]; then
    echo -e "  ${GREEN}✓${NC} Credential offer sent"
    echo -e "    Credential ID: $CREDENTIAL_ID"
    echo -e "    Type: $CREDENTIAL_TYPE"
else
    echo -e "  ${RED}✗${NC} Failed to create credential offer"
    echo "    Response: $CRED_RESPONSE"
    exit 1
fi
echo ""

# Step 7: Monitor Credential State
echo -e "${YELLOW}━━━ Step 7: Monitoring Credential Exchange ━━━${NC}"
echo -e "${CYAN}Please accept the credential offer in your mobile wallet${NC}"
echo ""

MAX_WAIT=180
WAIT_TIME=0

while [ $WAIT_TIME -lt $MAX_WAIT ]; do
    CRED_STATUS=$(curl -s -H "authorization: $API_KEY" "${BASE_URL}/didcomm/credentials/${CREDENTIAL_ID}")
    STATE=$(echo "$CRED_STATUS" | jq -r '.state // "unknown"')

    case "$STATE" in
        "done"|"credential-issued")
            echo ""
            echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
            echo -e "${GREEN}║         🎉 CREDENTIAL ISSUED SUCCESSFULLY! 🎉                 ║${NC}"
            echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
            echo ""
            echo "The credential is now in the holder's wallet."
            echo ""

            # Get final credential details
            FORM_DATA=$(curl -s -H "authorization: $API_KEY" "${BASE_URL}/didcomm/credentials/${CREDENTIAL_ID}/form-data")

            if echo "$FORM_DATA" | jq -e '.credential.jsonld.proof' > /dev/null 2>&1; then
                echo -e "${CYAN}Issued Credential:${NC}"
                echo "$FORM_DATA" | jq '.credential.jsonld'
            fi

            echo ""
            echo "━━━ Summary ━━━"
            echo "  Credential ID:   $CREDENTIAL_ID"
            echo "  Type:            $CREDENTIAL_TYPE"
            echo "  Issuer:          $ISSUER_DID"
            echo "  Holder:          $HOLDER_DID"
            echo "  Connection:      $CONNECTION_ID"
            echo ""

            # Step 8: Generate Verification QR Code
            echo -e "${YELLOW}━━━ Step 8: Generate Verification QR Code ━━━${NC}"
            echo ""

            # Save credential to file
            CREDENTIAL_FILE="/tmp/credebl_credential_${CREDENTIAL_ID}.json"
            echo "$FORM_DATA" | jq '.credential.jsonld' > "$CREDENTIAL_FILE"

            if [ ! -s "$CREDENTIAL_FILE" ]; then
                echo -e "  ${RED}✗${NC} Could not save credential to file"
                exit 0
            fi

            echo -e "  ${GREEN}✓${NC} Credential saved to: $CREDENTIAL_FILE"

            # Check for PixelPass (for Inji Verify compatibility)
            PIXELPASS_AVAILABLE=false
            PIXELPASS_DIR="/tmp/pixelpass_env"

            if command -v node &> /dev/null; then
                # Check if PixelPass is installed in our local directory
                if [ -d "$PIXELPASS_DIR/node_modules/@injistack/pixelpass" ]; then
                    PIXELPASS_AVAILABLE=true
                else
                    # Try to install it
                    echo -e "  ${CYAN}Installing PixelPass for Inji compatibility...${NC}"
                    mkdir -p "$PIXELPASS_DIR"
                    (cd "$PIXELPASS_DIR" && npm init -y > /dev/null 2>&1 && npm install @injistack/pixelpass --silent 2>/dev/null)
                    if [ -d "$PIXELPASS_DIR/node_modules/@injistack/pixelpass" ]; then
                        PIXELPASS_AVAILABLE=true
                        echo -e "  ${GREEN}✓${NC} PixelPass installed"
                    fi
                fi
            fi

            if [ "$PIXELPASS_AVAILABLE" = true ]; then
                echo -e "  ${GREEN}✓${NC} PixelPass detected - generating Inji-compatible QR"

                QRDATA_FILE="/tmp/credebl_qrdata_${CREDENTIAL_ID}.txt"
                QR_PNG="/tmp/credebl_verification_qr_${CREDENTIAL_ID}.png"

                # Encode with PixelPass (run from pixelpass directory to find module)
                (cd "$PIXELPASS_DIR" && node -e "
const { generateQRData } = require('@injistack/pixelpass');
const fs = require('fs');
const credential = JSON.parse(fs.readFileSync('$CREDENTIAL_FILE', 'utf8'));
process.stdout.write(generateQRData(JSON.stringify(credential)));
") > "$QRDATA_FILE" 2>/dev/null

                if [ -s "$QRDATA_FILE" ]; then
                    echo -e "  ${GREEN}✓${NC} Credential encoded with PixelPass"

                    # Generate PNG if qrencode is available
                    if command -v qrencode &> /dev/null; then
                        qrencode -o "$QR_PNG" -s 10 -m 2 < "$QRDATA_FILE"
                        echo -e "  ${GREEN}✓${NC} QR code image saved to: $QR_PNG"
                    fi

                    # Display ASCII QR in terminal
                    if command -v qrencode &> /dev/null; then
                        echo ""
                        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                        echo -e "${YELLOW}  Scan this QR code with Inji Verify to verify the credential${NC}"
                        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                        echo ""
                        qrencode -t ANSIUTF8 < "$QRDATA_FILE"
                    fi
                else
                    echo -e "  ${YELLOW}⚠${NC} PixelPass encoding failed, falling back to raw credential QR"
                    PIXELPASS_AVAILABLE=false
                fi
            fi

            # Fallback: Generate QR from raw credential JSON (less compatible but works)
            if [ "$PIXELPASS_AVAILABLE" = false ]; then
                echo -e "  ${YELLOW}⚠${NC} PixelPass not available - generating basic credential QR"
                echo -e "    Install for Inji compatibility: npm install -g @injistack/pixelpass"

                if command -v qrencode &> /dev/null; then
                    QR_PNG="/tmp/credebl_verification_qr_${CREDENTIAL_ID}.png"
                    # QR from raw JSON (may be too large for complex credentials)
                    cat "$CREDENTIAL_FILE" | jq -c . | qrencode -o "$QR_PNG" -s 6 -m 2 2>/dev/null

                    if [ -f "$QR_PNG" ]; then
                        echo -e "  ${GREEN}✓${NC} Basic QR code saved to: $QR_PNG"
                    fi
                else
                    echo -e "  ${YELLOW}⚠${NC} qrencode not installed - cannot generate QR image"
                    echo -e "    Install with: sudo apt install qrencode"
                fi
            fi

            echo ""
            echo -e "${GREEN}━━━ Verification QR Generation Complete ━━━${NC}"
            echo ""
            echo "Files generated:"
            echo "  - Credential JSON: $CREDENTIAL_FILE"
            [ -f "$QR_PNG" ] && echo "  - QR Code Image:   $QR_PNG"
            [ -f "$QRDATA_FILE" ] && echo "  - QR Data:         $QRDATA_FILE"
            echo ""

            # Offer to serve QR code for download
            if [ -f "$QR_PNG" ]; then
                echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                echo -e "${YELLOW}  Download QR Code Image${NC}"
                echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                echo ""
                echo "Options:"
                echo "  1. View locally:  xdg-open $QR_PNG"
                echo ""

                # Get local IP for download link
                LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
                if [ -z "$LOCAL_IP" ]; then
                    LOCAL_IP="localhost"
                fi

                echo -n "Would you like to start a download server? (y/N): "
                read -r SERVE_CHOICE

                if [[ "$SERVE_CHOICE" =~ ^[Yy]$ ]]; then
                    # Copy QR to a simple filename for easier download
                    QR_SERVE_DIR="/tmp/credebl_qr_serve"
                    mkdir -p "$QR_SERVE_DIR"
                    cp "$QR_PNG" "$QR_SERVE_DIR/verification-qr.png"
                    [ -f "$CREDENTIAL_FILE" ] && cp "$CREDENTIAL_FILE" "$QR_SERVE_DIR/credential.json"

                    # Find available port
                    SERVE_PORT=8888
                    while lsof -i:$SERVE_PORT &>/dev/null; do
                        SERVE_PORT=$((SERVE_PORT + 1))
                    done

                    echo ""
                    echo -e "${GREEN}Starting download server on port $SERVE_PORT...${NC}"
                    echo ""
                    echo -e "${CYAN}Download links (accessible from any device on your network):${NC}"
                    echo ""
                    echo -e "  QR Code Image:  ${GREEN}http://${LOCAL_IP}:${SERVE_PORT}/verification-qr.png${NC}"
                    echo -e "  Credential JSON: ${GREEN}http://${LOCAL_IP}:${SERVE_PORT}/credential.json${NC}"
                    echo ""
                    echo -e "${YELLOW}Press Ctrl+C to stop the server when done${NC}"
                    echo ""

                    # Start Python HTTP server
                    cd "$QR_SERVE_DIR"
                    python3 -m http.server $SERVE_PORT 2>/dev/null || python -m SimpleHTTPServer $SERVE_PORT 2>/dev/null
                fi
            fi

            echo ""
            echo "To view the QR code image locally:"
            [ -f "$QR_PNG" ] && echo "  xdg-open $QR_PNG"
            echo ""

            exit 0
            ;;
        "offer-sent")
            printf "\r  ⏳ Waiting for holder to accept offer... (%ds)" $WAIT_TIME
            ;;
        "request-received")
            printf "\r  📨 Processing credential request... (%ds)      " $WAIT_TIME
            ;;
        *)
            printf "\r  State: %s (%ds)                    " "$STATE" $WAIT_TIME
            ;;
    esac

    sleep 3
    WAIT_TIME=$((WAIT_TIME + 3))
done

echo ""
echo -e "${RED}✗ Timeout waiting for credential exchange to complete${NC}"
echo "  Final state: $STATE"
echo ""
echo "Check agent logs for errors:"
echo "  docker logs YOUR_CONTAINER_NAME 2>&1 | tail -50"
exit 1
