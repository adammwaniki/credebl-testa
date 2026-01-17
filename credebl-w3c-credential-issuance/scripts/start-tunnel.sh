#!/bin/bash
#
# CREDEBL SSH Tunnel Script
# Creates a public endpoint for the credo-controller DIDComm port
#
# Usage: ./start-tunnel.sh [port] [log_file]
#
# Arguments:
#   port     - Local port to tunnel (default: 9004)
#   log_file - Log file path (default: /tmp/credebl-tunnel.log)
#

set -e

# Configuration
LOCAL_PORT="${1:-9004}"
LOG_FILE="${2:-/tmp/credebl-tunnel.log}"
TUNNEL_SERVICE="localhost.run"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  CREDEBL SSH Tunnel Script${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if there's an existing tunnel
EXISTING_PID=$(pgrep -f "ssh.*localhost.run.*${LOCAL_PORT}" 2>/dev/null || true)
if [ -n "$EXISTING_PID" ]; then
    echo -e "${YELLOW}Found existing tunnel process: $EXISTING_PID${NC}"
    read -p "Kill existing tunnel? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        kill $EXISTING_PID 2>/dev/null || true
        sleep 2
        echo -e "${GREEN}Killed existing tunnel${NC}"
    else
        echo -e "${RED}Please stop existing tunnel first${NC}"
        exit 1
    fi
fi

# Start the tunnel
echo -e "${BLUE}Starting SSH tunnel...${NC}"
echo "  Local Port: $LOCAL_PORT"
echo "  Service: $TUNNEL_SERVICE"
echo "  Log File: $LOG_FILE"
echo ""

# Remove old log file
rm -f "$LOG_FILE"

# Start tunnel in background
nohup ssh -o StrictHostKeyChecking=no -o ServerAliveInterval=60 -o ServerAliveCountMax=3 \
    -R 80:localhost:${LOCAL_PORT} localhost.run > "$LOG_FILE" 2>&1 &

TUNNEL_PID=$!
echo "Tunnel PID: $TUNNEL_PID"

# Wait for tunnel to establish and extract URL
echo -e "${YELLOW}Waiting for tunnel to establish...${NC}"
RETRY=0
MAX_RETRIES=30
TUNNEL_URL=""

while [ $RETRY -lt $MAX_RETRIES ]; do
    sleep 1
    RETRY=$((RETRY + 1))

    # Check if process is still running
    if ! kill -0 $TUNNEL_PID 2>/dev/null; then
        echo -e "${RED}Tunnel process died. Check log file: $LOG_FILE${NC}"
        cat "$LOG_FILE"
        exit 1
    fi

    # Try to extract URL from log
    TUNNEL_URL=$(grep -oE 'https://[a-z0-9]+\.lhr\.life' "$LOG_FILE" 2>/dev/null | head -1 || true)

    if [ -n "$TUNNEL_URL" ]; then
        break
    fi

    echo -n "."
done
echo ""

if [ -z "$TUNNEL_URL" ]; then
    echo -e "${RED}Failed to extract tunnel URL after $MAX_RETRIES seconds${NC}"
    echo "Log contents:"
    cat "$LOG_FILE"
    exit 1
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Tunnel Established Successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "  ${BLUE}Public URL:${NC} $TUNNEL_URL"
echo -e "  ${BLUE}Local Port:${NC} $LOCAL_PORT"
echo -e "  ${BLUE}Process ID:${NC} $TUNNEL_PID"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "  1. Update your agent config endpoint to: $TUNNEL_URL"
echo "  2. Restart your agent container"
echo "  3. Verify with: curl $TUNNEL_URL"
echo ""

# Save URL to file for easy access
URL_FILE="/tmp/credebl-tunnel-url.txt"
echo "$TUNNEL_URL" > "$URL_FILE"
echo -e "URL saved to: $URL_FILE"
echo ""

# Output for copying
echo -e "${BLUE}Copy-paste commands:${NC}"
echo ""
echo "# Update agent config (modify path as needed):"
echo "sed -i 's|\"endpoint\": \\[\"[^\"]*\"\\]|\"endpoint\": [\"$TUNNEL_URL\"]|' /path/to/agent-config.json"
echo ""
echo "# Restart container:"
echo "docker restart YOUR_CONTAINER_NAME"
echo ""

# Monitor tunnel in background
echo -e "${YELLOW}Monitoring tunnel... Press Ctrl+C to stop.${NC}"
echo ""

# Keep script running and show connection status
while true; do
    if ! kill -0 $TUNNEL_PID 2>/dev/null; then
        echo -e "${RED}Tunnel process died!${NC}"
        echo "Attempting to restart..."
        exec "$0" "$LOCAL_PORT" "$LOG_FILE"
    fi

    # Test tunnel every 30 seconds
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$TUNNEL_URL" 2>/dev/null || echo "000")

    if [ "$HTTP_CODE" = "503" ]; then
        echo -e "${RED}$(date): Tunnel returned 503 - may need restart${NC}"
    elif [ "$HTTP_CODE" = "000" ]; then
        echo -e "${YELLOW}$(date): Cannot reach tunnel${NC}"
    else
        echo -e "${GREEN}$(date): Tunnel healthy (HTTP $HTTP_CODE)${NC}"
    fi

    sleep 30
done
