#!/bin/bash
# generate-verification-qr.sh - Generate Inji Verify compatible QR code from a credential
#
# Usage: ./generate-verification-qr.sh [OPTIONS] <credential-file>
#   -o, --output FILE    Output QR code PNG file
#   -d, --display        Display ASCII QR in terminal
#   -s, --serve          Start HTTP server to download QR
#   -h, --help           Show this help message
#
# This script uses @injistack/pixelpass to encode credentials in CBOR format
# compatible with Inji Verify mobile app.
#
# Example:
#   ./generate-verification-qr.sh /tmp/employment-credential-123.json -d
#   ./generate-verification-qr.sh /tmp/credential.json -o /tmp/my-qr.png -s

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Default values
CREDENTIAL_FILE=""
OUTPUT_FILE=""
DISPLAY_ASCII=false
SERVE_QR=false
PIXELPASS_DIR="/tmp/pixelpass_env"

show_help() {
    head -16 "$0" | tail -13
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -d|--display)
            DISPLAY_ASCII=true
            shift
            ;;
        -s|--serve)
            SERVE_QR=true
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
            CREDENTIAL_FILE="$1"
            shift
            ;;
    esac
done

# Validate input
if [ -z "$CREDENTIAL_FILE" ]; then
    echo -e "${RED}Error: Credential file is required${NC}"
    echo "Usage: $0 <credential-file> [options]"
    exit 1
fi

if [ ! -f "$CREDENTIAL_FILE" ]; then
    echo -e "${RED}Error: File not found: $CREDENTIAL_FILE${NC}"
    exit 1
fi

# Set default output file if not specified
if [ -z "$OUTPUT_FILE" ]; then
    BASENAME=$(basename "$CREDENTIAL_FILE" .json)
    OUTPUT_FILE="/tmp/${BASENAME}-qr.png"
fi

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     Inji Verify Compatible QR Code Generator                   ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}Input:${NC}  $CREDENTIAL_FILE"
echo -e "  ${CYAN}Output:${NC} $OUTPUT_FILE"
echo ""

# Check dependencies
if ! command -v node &> /dev/null; then
    echo -e "${RED}Error: Node.js is required but not installed${NC}"
    echo "  Install with: sudo apt install nodejs npm"
    exit 1
fi

if ! command -v qrencode &> /dev/null; then
    echo -e "${YELLOW}Warning: qrencode not installed - will only generate data file${NC}"
    echo "  Install with: sudo apt install qrencode"
fi

# Ensure PixelPass is installed
echo -e "${YELLOW}━━━ Step 1: Setting up PixelPass ━━━${NC}"

if [ -d "$PIXELPASS_DIR/node_modules/@injistack/pixelpass" ]; then
    echo -e "  ${GREEN}✓${NC} PixelPass already installed"
else
    echo -e "  ${CYAN}Installing PixelPass...${NC}"
    mkdir -p "$PIXELPASS_DIR"
    (cd "$PIXELPASS_DIR" && npm init -y > /dev/null 2>&1 && npm install @injistack/pixelpass --silent 2>/dev/null)

    if [ -d "$PIXELPASS_DIR/node_modules/@injistack/pixelpass" ]; then
        echo -e "  ${GREEN}✓${NC} PixelPass installed successfully"
    else
        echo -e "${RED}Error: Failed to install PixelPass${NC}"
        echo "  Try manually: cd $PIXELPASS_DIR && npm install @injistack/pixelpass"
        exit 1
    fi
fi
echo ""

# Generate CBOR-encoded QR data
echo -e "${YELLOW}━━━ Step 2: Encoding Credential with PixelPass ━━━${NC}"

QRDATA_FILE="${OUTPUT_FILE%.png}.txt"

# Read and validate the credential JSON
if ! jq empty "$CREDENTIAL_FILE" 2>/dev/null; then
    echo -e "${RED}Error: Invalid JSON in credential file${NC}"
    exit 1
fi

# Encode with PixelPass
(cd "$PIXELPASS_DIR" && node -e "
const { generateQRData } = require('@injistack/pixelpass');
const fs = require('fs');
try {
    const credential = JSON.parse(fs.readFileSync('$CREDENTIAL_FILE', 'utf8'));
    const qrData = generateQRData(JSON.stringify(credential));
    process.stdout.write(qrData);
} catch (error) {
    console.error('Error:', error.message);
    process.exit(1);
}
") > "$QRDATA_FILE" 2>/dev/null

if [ ! -s "$QRDATA_FILE" ]; then
    echo -e "${RED}Error: PixelPass encoding failed${NC}"
    exit 1
fi

QRDATA_SIZE=$(wc -c < "$QRDATA_FILE")
echo -e "  ${GREEN}✓${NC} Credential encoded (${QRDATA_SIZE} bytes)"
echo -e "  ${GREEN}✓${NC} QR data saved to: $QRDATA_FILE"
echo ""

# Generate QR code image
echo -e "${YELLOW}━━━ Step 3: Generating QR Code ━━━${NC}"

if command -v qrencode &> /dev/null; then
    qrencode -o "$OUTPUT_FILE" -s 10 -m 2 < "$QRDATA_FILE"

    if [ -f "$OUTPUT_FILE" ]; then
        echo -e "  ${GREEN}✓${NC} QR code image saved to: $OUTPUT_FILE"
    else
        echo -e "${RED}Error: Failed to generate QR code image${NC}"
    fi
else
    echo -e "  ${YELLOW}⚠${NC} qrencode not available - skipping PNG generation"
fi
echo ""

# Display ASCII QR in terminal
if [ "$DISPLAY_ASCII" = true ] && command -v qrencode &> /dev/null; then
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}  Scan with Inji Verify to verify the credential${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    qrencode -t ANSIUTF8 < "$QRDATA_FILE"
    echo ""
fi

# Serve QR code for download
if [ "$SERVE_QR" = true ] && [ -f "$OUTPUT_FILE" ]; then
    echo -e "${YELLOW}━━━ Starting Download Server ━━━${NC}"

    QR_SERVE_DIR="/tmp/credebl_qr_serve"
    mkdir -p "$QR_SERVE_DIR"
    cp "$OUTPUT_FILE" "$QR_SERVE_DIR/verification-qr.png"
    cp "$CREDENTIAL_FILE" "$QR_SERVE_DIR/credential.json"
    cp "$QRDATA_FILE" "$QR_SERVE_DIR/qr-data.txt"

    # Find available port
    SERVE_PORT=8888
    while lsof -i:$SERVE_PORT &>/dev/null 2>&1; do
        SERVE_PORT=$((SERVE_PORT + 1))
    done

    # Get local IP
    LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [ -z "$LOCAL_IP" ]; then
        LOCAL_IP="localhost"
    fi

    echo ""
    echo -e "${CYAN}Download links (accessible from any device on your network):${NC}"
    echo ""
    echo -e "  QR Code Image:   ${GREEN}http://${LOCAL_IP}:${SERVE_PORT}/verification-qr.png${NC}"
    echo -e "  Credential JSON: ${GREEN}http://${LOCAL_IP}:${SERVE_PORT}/credential.json${NC}"
    echo -e "  QR Data:         ${GREEN}http://${LOCAL_IP}:${SERVE_PORT}/qr-data.txt${NC}"
    echo ""
    echo -e "${YELLOW}Press Ctrl+C to stop the server${NC}"
    echo ""

    cd "$QR_SERVE_DIR"
    python3 -m http.server $SERVE_PORT 2>/dev/null
fi

# Summary
echo ""
echo -e "${GREEN}━━━ QR Generation Complete ━━━${NC}"
echo ""
echo "Files generated:"
echo "  - QR Data:      $QRDATA_FILE"
[ -f "$OUTPUT_FILE" ] && echo "  - QR Image:     $OUTPUT_FILE"
echo ""
echo "To view the QR code:"
[ -f "$OUTPUT_FILE" ] && echo "  xdg-open $OUTPUT_FILE"
echo ""
echo "To display in terminal:"
echo "  qrencode -t ANSIUTF8 < $QRDATA_FILE"
echo ""
