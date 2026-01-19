#!/bin/bash
#
# Start CREDEBL-Inji Adapter with SSH Tunnel
#
# This script:
# 1. Starts the adapter service locally
# 2. Establishes an SSH reverse tunnel to the Inji Verify server
# 3. Monitors both and restarts if needed
#
# Usage: ./start-adapter-tunnel.sh [options]
#
# Prerequisites:
# - SSH access to Inji Verify server
# - Node.js installed locally
# - CREDEBL agent running locally

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Default configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADAPTER_DIR="$(dirname "$SCRIPT_DIR")/adapter"

# Configuration - override with environment variables or command line
INJI_SERVER="${INJI_SERVER:-}"
INJI_USER="${INJI_USER:-root}"
ADAPTER_PORT="${ADAPTER_PORT:-8085}"
CREDEBL_AGENT_URL="${CREDEBL_AGENT_URL:-http://localhost:8004}"
CREDEBL_API_KEY="${CREDEBL_API_KEY:-}"
SSH_KEY="${SSH_KEY:-}"
KEEP_ALIVE_INTERVAL="${KEEP_ALIVE_INTERVAL:-30}"
BACKGROUND="${BACKGROUND:-false}"

# PID files
PID_DIR="/tmp/credebl-adapter"
ADAPTER_PID_FILE="$PID_DIR/adapter.pid"
TUNNEL_PID_FILE="$PID_DIR/tunnel.pid"
LOG_FILE="$PID_DIR/adapter.log"

show_help() {
    cat << EOF
CREDEBL-Inji Adapter Tunnel Setup

This script starts the adapter service locally and establishes an SSH tunnel
to make it accessible from the Inji Verify server.

Usage: $0 [options]

Options:
  -s, --server HOST      Inji Verify server hostname/IP (required)
  -u, --user USER        SSH username (default: root)
  -p, --port PORT        Adapter port (default: 8085)
  -a, --agent-url URL    CREDEBL agent URL (default: http://localhost:8004)
  -k, --api-key KEY      CREDEBL API key (required)
  -i, --identity FILE    SSH identity file (private key)
  -b, --background       Run in background (daemonize)
  --stop                 Stop running adapter and tunnel
  --status               Check status of adapter and tunnel
  -h, --help             Show this help

Environment Variables:
  INJI_SERVER           Inji Verify server hostname/IP
  INJI_USER             SSH username
  ADAPTER_PORT          Adapter listen port
  CREDEBL_AGENT_URL     CREDEBL agent base URL
  CREDEBL_API_KEY       CREDEBL agent API key
  SSH_KEY               Path to SSH private key

Examples:
  # Start with all options
  $0 -s 159.89.164.7 -k "your-api-key" -i ~/.ssh/id_rsa

  # Start using environment variables
  export INJI_SERVER=159.89.164.7
  export CREDEBL_API_KEY="your-api-key"
  $0

  # Run in background
  $0 -s 159.89.164.7 -k "your-api-key" -b

  # Check status
  $0 --status

  # Stop services
  $0 --stop

EOF
    exit 0
}

# Parse arguments
ACTION="start"
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--server) INJI_SERVER="$2"; shift 2 ;;
        -u|--user) INJI_USER="$2"; shift 2 ;;
        -p|--port) ADAPTER_PORT="$2"; shift 2 ;;
        -a|--agent-url) CREDEBL_AGENT_URL="$2"; shift 2 ;;
        -k|--api-key) CREDEBL_API_KEY="$2"; shift 2 ;;
        -i|--identity) SSH_KEY="$2"; shift 2 ;;
        -b|--background) BACKGROUND="true"; shift ;;
        --stop) ACTION="stop"; shift ;;
        --status) ACTION="status"; shift ;;
        -h|--help) show_help ;;
        *) echo -e "${RED}Unknown option: $1${NC}"; show_help ;;
    esac
done

# Ensure PID directory exists
mkdir -p "$PID_DIR"

# Function to check if process is running
is_running() {
    local pid_file="$1"
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

# Function to stop services
stop_services() {
    echo -e "${YELLOW}Stopping services...${NC}"

    # Stop adapter
    if [ -f "$ADAPTER_PID_FILE" ]; then
        local pid=$(cat "$ADAPTER_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null
            echo -e "  ${GREEN}✓${NC} Stopped adapter (PID: $pid)"
        fi
        rm -f "$ADAPTER_PID_FILE"
    else
        # Try to find and kill by process name
        pkill -f "node.*adapter.js" 2>/dev/null && echo -e "  ${GREEN}✓${NC} Stopped adapter process"
    fi

    # Stop SSH tunnel
    if [ -f "$TUNNEL_PID_FILE" ]; then
        local pid=$(cat "$TUNNEL_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null
            echo -e "  ${GREEN}✓${NC} Stopped SSH tunnel (PID: $pid)"
        fi
        rm -f "$TUNNEL_PID_FILE"
    else
        # Try to find and kill by pattern
        pkill -f "ssh.*-R.*$ADAPTER_PORT" 2>/dev/null && echo -e "  ${GREEN}✓${NC} Stopped SSH tunnel process"
    fi

    echo -e "${GREEN}Services stopped${NC}"
}

# Function to show status
show_status() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              Adapter & Tunnel Status                           ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Check adapter
    echo -n "  Adapter service:    "
    if is_running "$ADAPTER_PID_FILE"; then
        local pid=$(cat "$ADAPTER_PID_FILE")
        echo -e "${GREEN}RUNNING${NC} (PID: $pid)"
    elif pgrep -f "node.*adapter.js" > /dev/null; then
        echo -e "${GREEN}RUNNING${NC} (found by process name)"
    else
        echo -e "${RED}STOPPED${NC}"
    fi

    # Check tunnel
    echo -n "  SSH tunnel:         "
    if is_running "$TUNNEL_PID_FILE"; then
        local pid=$(cat "$TUNNEL_PID_FILE")
        echo -e "${GREEN}RUNNING${NC} (PID: $pid)"
    elif pgrep -f "ssh.*-R.*$ADAPTER_PORT" > /dev/null; then
        echo -e "${GREEN}RUNNING${NC} (found by process name)"
    else
        echo -e "${RED}STOPPED${NC}"
    fi

    # Check adapter health
    echo -n "  Adapter health:     "
    if curl -s --max-time 3 "http://localhost:$ADAPTER_PORT/health" | grep -q "ok"; then
        echo -e "${GREEN}HEALTHY${NC}"
    else
        echo -e "${RED}UNHEALTHY${NC}"
    fi

    # Check remote tunnel if server is known
    if [ -n "$INJI_SERVER" ]; then
        echo -n "  Remote tunnel:      "
        if ssh -o ConnectTimeout=5 -o BatchMode=yes "${INJI_USER}@${INJI_SERVER}" \
            "curl -s --max-time 3 http://localhost:$ADAPTER_PORT/health" 2>/dev/null | grep -q "ok"; then
            echo -e "${GREEN}CONNECTED${NC}"
        else
            echo -e "${RED}NOT CONNECTED${NC}"
        fi
    fi

    echo ""

    # Show log tail if exists
    if [ -f "$LOG_FILE" ]; then
        echo -e "${CYAN}Recent logs:${NC}"
        tail -5 "$LOG_FILE" | sed 's/^/  /'
        echo ""
    fi
}

# Handle action
case "$ACTION" in
    stop)
        stop_services
        exit 0
        ;;
    status)
        show_status
        exit 0
        ;;
esac

# Validate required inputs for start
if [ -z "$INJI_SERVER" ]; then
    echo -e "${RED}Error: Inji server hostname/IP is required${NC}"
    echo "Use -s/--server option or set INJI_SERVER environment variable"
    exit 1
fi

if [ -z "$CREDEBL_API_KEY" ]; then
    echo -e "${RED}Error: CREDEBL API key is required${NC}"
    echo "Use -k/--api-key option or set CREDEBL_API_KEY environment variable"
    exit 1
fi

# Check if adapter.js exists
if [ ! -f "$ADAPTER_DIR/adapter.js" ]; then
    echo -e "${RED}Error: adapter.js not found at $ADAPTER_DIR${NC}"
    exit 1
fi

# Build SSH options
SSH_OPTS="-o StrictHostKeyChecking=no -o ServerAliveInterval=$KEEP_ALIVE_INTERVAL -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes"
if [ -n "$SSH_KEY" ]; then
    SSH_OPTS="$SSH_OPTS -i $SSH_KEY"
fi

# Header
echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║       CREDEBL-Inji Adapter Tunnel Setup                        ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}Inji Server:${NC}      $INJI_SERVER"
echo -e "  ${CYAN}Adapter Port:${NC}     $ADAPTER_PORT"
echo -e "  ${CYAN}CREDEBL Agent:${NC}    $CREDEBL_AGENT_URL"
echo -e "  ${CYAN}Background:${NC}       $BACKGROUND"
echo ""

# Stop any existing services
echo -e "${YELLOW}━━━ Step 1: Cleaning up existing processes ━━━${NC}"
stop_services 2>/dev/null || true
sleep 1
echo ""

# Check CREDEBL agent connectivity
echo -e "${YELLOW}━━━ Step 2: Checking CREDEBL Agent ━━━${NC}"
if curl -s --max-time 5 -H "Authorization: $CREDEBL_API_KEY" "$CREDEBL_AGENT_URL/agent" | grep -q "isInitialized"; then
    echo -e "  ${GREEN}✓${NC} CREDEBL agent is accessible"
else
    echo -e "  ${RED}✗${NC} Cannot reach CREDEBL agent at $CREDEBL_AGENT_URL"
    echo "    Make sure the agent is running and the API key is correct"
    exit 1
fi
echo ""

# Check SSH connectivity
echo -e "${YELLOW}━━━ Step 3: Checking SSH Connectivity ━━━${NC}"
if ssh $SSH_OPTS -o ConnectTimeout=10 -o BatchMode=yes "${INJI_USER}@${INJI_SERVER}" "echo 'SSH OK'" 2>/dev/null | grep -q "OK"; then
    echo -e "  ${GREEN}✓${NC} SSH connection to $INJI_SERVER successful"
else
    echo -e "  ${RED}✗${NC} Cannot SSH to ${INJI_USER}@${INJI_SERVER}"
    echo "    Check SSH credentials and network connectivity"
    exit 1
fi

# Kill any existing tunnel on remote port
echo -e "  Clearing remote port $ADAPTER_PORT..."
ssh $SSH_OPTS "${INJI_USER}@${INJI_SERVER}" "fuser -k $ADAPTER_PORT/tcp 2>/dev/null || true" 2>/dev/null
sleep 1
echo ""

# Start adapter
echo -e "${YELLOW}━━━ Step 4: Starting Adapter Service ━━━${NC}"

if [ "$BACKGROUND" = "true" ]; then
    # Background mode
    cd "$ADAPTER_DIR"
    ADAPTER_PORT="$ADAPTER_PORT" \
    CREDEBL_AGENT_URL="$CREDEBL_AGENT_URL" \
    CREDEBL_API_KEY="$CREDEBL_API_KEY" \
    nohup node adapter.js >> "$LOG_FILE" 2>&1 &
    ADAPTER_PID=$!
    echo "$ADAPTER_PID" > "$ADAPTER_PID_FILE"
    echo -e "  ${GREEN}✓${NC} Adapter started in background (PID: $ADAPTER_PID)"
else
    # Foreground - start in subshell
    cd "$ADAPTER_DIR"
    ADAPTER_PORT="$ADAPTER_PORT" \
    CREDEBL_AGENT_URL="$CREDEBL_AGENT_URL" \
    CREDEBL_API_KEY="$CREDEBL_API_KEY" \
    node adapter.js &
    ADAPTER_PID=$!
    echo "$ADAPTER_PID" > "$ADAPTER_PID_FILE"
    echo -e "  ${GREEN}✓${NC} Adapter started (PID: $ADAPTER_PID)"
fi

# Wait for adapter to be ready
sleep 2
if curl -s --max-time 5 "http://localhost:$ADAPTER_PORT/health" | grep -q "ok"; then
    echo -e "  ${GREEN}✓${NC} Adapter health check passed"
else
    echo -e "  ${RED}✗${NC} Adapter health check failed"
    cat "$LOG_FILE" 2>/dev/null | tail -10
    exit 1
fi
echo ""

# Start SSH tunnel
echo -e "${YELLOW}━━━ Step 5: Establishing SSH Tunnel ━━━${NC}"

if [ "$BACKGROUND" = "true" ]; then
    # Background tunnel with autossh-like behavior
    ssh -f -N -R "$ADAPTER_PORT:localhost:$ADAPTER_PORT" $SSH_OPTS "${INJI_USER}@${INJI_SERVER}"
    TUNNEL_PID=$(pgrep -f "ssh.*-R.*$ADAPTER_PORT:localhost:$ADAPTER_PORT.*$INJI_SERVER" | head -1)
    echo "$TUNNEL_PID" > "$TUNNEL_PID_FILE"
    echo -e "  ${GREEN}✓${NC} SSH tunnel established in background (PID: $TUNNEL_PID)"
else
    ssh -f -N -R "$ADAPTER_PORT:localhost:$ADAPTER_PORT" $SSH_OPTS "${INJI_USER}@${INJI_SERVER}"
    TUNNEL_PID=$(pgrep -f "ssh.*-R.*$ADAPTER_PORT:localhost:$ADAPTER_PORT.*$INJI_SERVER" | head -1)
    echo "$TUNNEL_PID" > "$TUNNEL_PID_FILE"
    echo -e "  ${GREEN}✓${NC} SSH tunnel established (PID: $TUNNEL_PID)"
fi

sleep 2
echo ""

# Verify tunnel
echo -e "${YELLOW}━━━ Step 6: Verifying Tunnel Connection ━━━${NC}"
if ssh $SSH_OPTS "${INJI_USER}@${INJI_SERVER}" "curl -s --max-time 5 http://localhost:$ADAPTER_PORT/health" 2>/dev/null | grep -q "ok"; then
    echo -e "  ${GREEN}✓${NC} Tunnel verified - adapter accessible from Inji server"
else
    echo -e "  ${YELLOW}⚠${NC} Could not verify tunnel - may need a moment to establish"
fi
echo ""

# Summary
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    Setup Complete!                             ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Services running:"
echo "  - Adapter:  localhost:$ADAPTER_PORT (PID: $ADAPTER_PID)"
echo "  - Tunnel:   $INJI_SERVER:$ADAPTER_PORT -> localhost:$ADAPTER_PORT (PID: $TUNNEL_PID)"
echo ""
echo "Log file: $LOG_FILE"
echo ""
echo "Commands:"
echo "  Check status:  $0 --status"
echo "  Stop services: $0 --stop"
echo "  View logs:     tail -f $LOG_FILE"
echo ""

if [ "$BACKGROUND" = "false" ]; then
    echo -e "${YELLOW}Running in foreground. Press Ctrl+C to stop.${NC}"
    echo ""

    # Wait for either process to exit
    cleanup() {
        echo ""
        echo -e "${YELLOW}Shutting down...${NC}"
        stop_services
        exit 0
    }
    trap cleanup SIGINT SIGTERM

    # Monitor processes
    while true; do
        if ! is_running "$ADAPTER_PID_FILE"; then
            echo -e "${RED}Adapter stopped unexpectedly${NC}"
            stop_services
            exit 1
        fi
        if ! is_running "$TUNNEL_PID_FILE"; then
            echo -e "${YELLOW}Tunnel disconnected, reconnecting...${NC}"
            ssh -f -N -R "$ADAPTER_PORT:localhost:$ADAPTER_PORT" $SSH_OPTS "${INJI_USER}@${INJI_SERVER}"
            TUNNEL_PID=$(pgrep -f "ssh.*-R.*$ADAPTER_PORT:localhost:$ADAPTER_PORT.*$INJI_SERVER" | head -1)
            echo "$TUNNEL_PID" > "$TUNNEL_PID_FILE"
        fi
        sleep 5
    done
fi
