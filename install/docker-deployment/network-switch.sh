#!/bin/bash
#
# network-switch.sh - Automatically update CREDEBL configs when switching networks
#
# This script:
# 1. Detects your current local IP address
# 2. Updates all configuration files with the new IP
# 3. Restarts Docker services
# 4. Starts the agent tunnel (lhr.life)
# 5. Starts the adapter and tunnel to Inji Verify server
# 6. Restarts the testa-agent with updated config
#
# Usage: ./network-switch.sh [options]
#   -i, --ip IP          Override auto-detected IP
#   -s, --skip-tunnels   Skip starting tunnels
#   --status             Show current status only
#   -h, --help           Show help
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CREDEBL_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Files that contain IP addresses
AGENT_CONFIG="$SCRIPT_DIR/apps/agent-provisioning/AFJ/agent-config/1445b78e-092c-445c-9f83-024b4d661b22_TestaIssuer002.json"
ENV_FILE="$SCRIPT_DIR/.env"
PLATFORM_ADMIN_CONFIG="$SCRIPT_DIR/apps/agent-provisioning/AFJ/agent-config/7b33d0ec-a521-40a4-9a30-42c64c1a3b4b_Platform-admin.json"

# Remote server for Inji Verify adapter tunnel
INJI_SERVER="159.89.164.7"
INJI_USER="root"

# Tunnel scripts
AGENT_TUNNEL_SCRIPT="$CREDEBL_ROOT/credebl-w3c-credential-issuance/scripts/start-tunnel.sh"
ADAPTER_DIR="$SCRIPT_DIR/patches/polygon-did-fix/adapter"

# State files
STATE_DIR="/tmp/credebl-network"
LAST_IP_FILE="$STATE_DIR/last-ip"
TUNNEL_URL_FILE="/tmp/credebl-tunnel-url.txt"

# Options
SKIP_TUNNELS=false
STATUS_ONLY=false
OVERRIDE_IP=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--ip) OVERRIDE_IP="$2"; shift 2 ;;
        -s|--skip-tunnels) SKIP_TUNNELS=true; shift ;;
        --status) STATUS_ONLY=true; shift ;;
        -h|--help)
            head -20 "$0" | tail -17
            exit 0
            ;;
        *) echo -e "${RED}Unknown option: $1${NC}"; exit 1 ;;
    esac
done

mkdir -p "$STATE_DIR"

# Function to get current local IP
get_current_ip() {
    # Try multiple methods to get the local IP
    local ip=""

    # Method 1: ip route (most reliable on Linux)
    ip=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[\d.]+' | head -1)

    # Method 2: hostname -I
    if [ -z "$ip" ]; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi

    # Method 3: ifconfig
    if [ -z "$ip" ]; then
        ip=$(ifconfig 2>/dev/null | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -1)
    fi

    echo "$ip"
}

# Function to get last known IP
get_last_ip() {
    if [ -f "$LAST_IP_FILE" ]; then
        cat "$LAST_IP_FILE"
    else
        # Try to extract from current config
        if [ -f "$AGENT_CONFIG" ]; then
            grep -oP '"walletUrl":\s*"\K[^:]+' "$AGENT_CONFIG" 2>/dev/null || echo ""
        fi
    fi
}

# Function to show status
show_status() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              CREDEBL Network Status                            ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    local current_ip=$(get_current_ip)
    local last_ip=$(get_last_ip)

    echo -e "  ${CYAN}Current IP:${NC}     $current_ip"
    echo -e "  ${CYAN}Last Known IP:${NC}  $last_ip"

    if [ "$current_ip" != "$last_ip" ]; then
        echo -e "  ${YELLOW}⚠ IP has changed! Run this script to update configs.${NC}"
    else
        echo -e "  ${GREEN}✓ IP unchanged${NC}"
    fi
    echo ""

    # Docker services
    echo -e "${CYAN}Docker Services:${NC}"
    local running=$(docker ps -q 2>/dev/null | wc -l)
    local total=$(docker ps -aq --filter "name=credebl\|agent\|service" 2>/dev/null | wc -l)
    echo -e "  Running: $running containers"

    # Check key services
    for svc in credebl-postgres credebl-nats credebl-redis api-gateway agent-service; do
        local status=$(docker inspect -f '{{.State.Status}}' "$svc" 2>/dev/null || echo "not found")
        if [ "$status" = "running" ]; then
            echo -e "    ${GREEN}✓${NC} $svc"
        else
            echo -e "    ${RED}✗${NC} $svc ($status)"
        fi
    done
    echo ""

    # Tunnels
    echo -e "${CYAN}Tunnels:${NC}"

    # Agent tunnel (lhr.life)
    if pgrep -f "ssh.*localhost.run" > /dev/null 2>&1; then
        local tunnel_url=$(cat "$TUNNEL_URL_FILE" 2>/dev/null || echo "unknown")
        echo -e "  ${GREEN}✓${NC} Agent tunnel: $tunnel_url"
    else
        echo -e "  ${RED}✗${NC} Agent tunnel: not running"
    fi

    # Adapter reverse tunnel (local adapter -> remote)
    if pgrep -f "ssh.*-R.*$INJI_SERVER" > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} Adapter reverse tunnel: localhost:8085 -> $INJI_SERVER:8085"
    else
        echo -e "  ${RED}✗${NC} Adapter reverse tunnel: not running"
    fi

    # Verify-service forward tunnel (remote verify-service -> local)
    if pgrep -f "ssh.*-L.*8080.*$INJI_SERVER" > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} Verify-service forward tunnel: localhost:8080 -> verify-service:8080"
    else
        echo -e "  ${RED}✗${NC} Verify-service forward tunnel: not running"
    fi
    echo ""

    # Adapter
    echo -e "${CYAN}Adapter:${NC}"
    if curl -s --max-time 2 http://localhost:8085/health | grep -q "ok"; then
        echo -e "  ${GREEN}✓${NC} Running on port 8085"
        # Check if upstream is configured
        if curl -s --max-time 2 http://localhost:8080/ > /dev/null 2>&1; then
            echo -e "  ${GREEN}✓${NC} Upstream verify-service reachable"
        else
            echo -e "  ${YELLOW}⚠${NC} Upstream verify-service not reachable (non-polygon credentials may fail)"
        fi
    else
        echo -e "  ${RED}✗${NC} Not running"
    fi
    echo ""

    # Testa agent
    echo -e "${CYAN}Testa Agent:${NC}"
    local agent_status=$(docker inspect -f '{{.State.Status}}' "testa-agent" 2>/dev/null || echo "not found")
    if [ "$agent_status" = "running" ]; then
        echo -e "  ${GREEN}✓${NC} Running"
    else
        echo -e "  ${RED}✗${NC} $agent_status"
    fi
    echo ""
}

# Show status if requested
if [ "$STATUS_ONLY" = true ]; then
    show_status
    exit 0
fi

# Main execution
echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║          CREDEBL Network Switch Script                         ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Get current IP
if [ -n "$OVERRIDE_IP" ]; then
    CURRENT_IP="$OVERRIDE_IP"
    echo -e "  ${CYAN}Using override IP:${NC} $CURRENT_IP"
else
    CURRENT_IP=$(get_current_ip)
    echo -e "  ${CYAN}Detected IP:${NC} $CURRENT_IP"
fi

if [ -z "$CURRENT_IP" ]; then
    echo -e "${RED}ERROR: Could not detect IP address${NC}"
    echo "Use -i/--ip to specify manually"
    exit 1
fi

LAST_IP=$(get_last_ip)
echo -e "  ${CYAN}Previous IP:${NC} ${LAST_IP:-unknown}"
echo ""

# Check if IP changed
if [ "$CURRENT_IP" = "$LAST_IP" ]; then
    echo -e "${GREEN}IP has not changed. Checking services...${NC}"
else
    echo -e "${YELLOW}IP changed from $LAST_IP to $CURRENT_IP${NC}"
fi
echo ""

# Step 1: Update configuration files
echo -e "${YELLOW}━━━ Step 1: Updating Configuration Files ━━━${NC}"

update_ip_in_file() {
    local file="$1"
    local old_ip="$2"
    local new_ip="$3"

    if [ -f "$file" ] && [ -n "$old_ip" ]; then
        if grep -q "$old_ip" "$file" 2>/dev/null; then
            # Use temp file approach to handle permissions
            local tmpfile=$(mktemp)
            sed "s/$old_ip/$new_ip/g" "$file" > "$tmpfile"
            cat "$tmpfile" > "$file" 2>/dev/null || sudo cp "$tmpfile" "$file"
            rm -f "$tmpfile"
            echo -e "  ${GREEN}✓${NC} Updated: $(basename "$file")"
            return 0
        fi
    fi
    return 1
}

# Update agent config
if [ -f "$AGENT_CONFIG" ] && [ -n "$LAST_IP" ]; then
    update_ip_in_file "$AGENT_CONFIG" "$LAST_IP" "$CURRENT_IP" || echo -e "  ${CYAN}→${NC} Agent config: no changes needed"
fi

# Update .env file
if [ -f "$ENV_FILE" ] && [ -n "$LAST_IP" ]; then
    update_ip_in_file "$ENV_FILE" "$LAST_IP" "$CURRENT_IP" || echo -e "  ${CYAN}→${NC} .env: no changes needed"
fi

# Update Platform admin config if exists
if [ -f "$PLATFORM_ADMIN_CONFIG" ] && [ -n "$LAST_IP" ]; then
    update_ip_in_file "$PLATFORM_ADMIN_CONFIG" "$LAST_IP" "$CURRENT_IP" || true
fi

# Save current IP for next time
echo "$CURRENT_IP" > "$LAST_IP_FILE"
echo ""

# Step 2: Restart Docker services
echo -e "${YELLOW}━━━ Step 2: Restarting Docker Services ━━━${NC}"
cd "$SCRIPT_DIR"

# Stop and start docker compose
docker compose down 2>/dev/null || true
sleep 2
docker compose up -d

# Wait for services to be healthy
echo -e "  Waiting for services to start..."
sleep 10

# Check how many are running
running=$(docker ps --filter "name=credebl\|service" --format "{{.Names}}" | wc -l)
echo -e "  ${GREEN}✓${NC} $running services started"
echo ""

# Step 3: Kill old tunnels and processes
echo -e "${YELLOW}━━━ Step 3: Cleaning Up Old Processes ━━━${NC}"

# Kill old tunnels
pkill -f "ssh.*localhost.run" 2>/dev/null && echo -e "  ${GREEN}✓${NC} Killed old agent tunnel" || true
pkill -f "ssh.*-R.*$INJI_SERVER" 2>/dev/null && echo -e "  ${GREEN}✓${NC} Killed old adapter reverse tunnel" || true
pkill -f "ssh.*-L.*8080.*$INJI_SERVER" 2>/dev/null && echo -e "  ${GREEN}✓${NC} Killed old verify-service forward tunnel" || true
pkill -f "node.*adapter.js" 2>/dev/null && echo -e "  ${GREEN}✓${NC} Killed old adapter" || true

# Remove old testa-agent container
docker rm -f testa-agent 2>/dev/null && echo -e "  ${GREEN}✓${NC} Removed old testa-agent" || true

sleep 2
echo ""

if [ "$SKIP_TUNNELS" = true ]; then
    echo -e "${YELLOW}Skipping tunnels (--skip-tunnels flag)${NC}"
else
    # Step 4: Start agent tunnel
    echo -e "${YELLOW}━━━ Step 4: Starting Agent Tunnel (lhr.life) ━━━${NC}"

    if [ -f "$AGENT_TUNNEL_SCRIPT" ]; then
        "$AGENT_TUNNEL_SCRIPT" &
        sleep 8

        if [ -f "$TUNNEL_URL_FILE" ]; then
            TUNNEL_URL=$(cat "$TUNNEL_URL_FILE")
            echo -e "  ${GREEN}✓${NC} Tunnel URL: $TUNNEL_URL"

            # Update agent config with new tunnel URL
            if [ -f "$AGENT_CONFIG" ]; then
                # Extract current endpoint
                OLD_ENDPOINT=$(grep -oP '"endpoint":\s*\[\s*"\K[^"]+' "$AGENT_CONFIG" || echo "")
                if [ -n "$OLD_ENDPOINT" ] && [ "$OLD_ENDPOINT" != "$TUNNEL_URL" ]; then
                    tmpfile=$(mktemp)
                    sed "s|$OLD_ENDPOINT|$TUNNEL_URL|g" "$AGENT_CONFIG" > "$tmpfile"
                    cat "$tmpfile" > "$AGENT_CONFIG" 2>/dev/null || sudo cp "$tmpfile" "$AGENT_CONFIG"
                    rm -f "$tmpfile"
                    echo -e "  ${GREEN}✓${NC} Updated agent endpoint to $TUNNEL_URL"
                fi
            fi
        else
            echo -e "  ${YELLOW}⚠${NC} Could not get tunnel URL"
        fi
    else
        echo -e "  ${RED}✗${NC} Tunnel script not found: $AGENT_TUNNEL_SCRIPT"
    fi
    echo ""

    # Step 5: Start adapter and tunnel
    echo -e "${YELLOW}━━━ Step 5: Starting Adapter & Tunnel to Inji Verify ━━━${NC}"

    # Get verify-service container IP on remote for forward tunnel
    echo -e "  Getting verify-service IP from remote..."
    VERIFY_SERVICE_IP=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$INJI_USER@$INJI_SERVER" \
        "docker inspect verify-service --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'" 2>/dev/null)

    if [ -z "$VERIFY_SERVICE_IP" ]; then
        echo -e "  ${YELLOW}⚠${NC} Could not get verify-service IP, using default"
        VERIFY_SERVICE_IP="172.18.0.3"
    else
        echo -e "  ${GREEN}✓${NC} verify-service IP: $VERIFY_SERVICE_IP"
    fi

    # Create forward tunnel for verify-service (adapter needs to reach it)
    echo -e "  Creating forward tunnel to verify-service..."
    pkill -f "ssh.*-L.*8080.*$INJI_SERVER" 2>/dev/null || true
    ssh -f -N -L 8080:$VERIFY_SERVICE_IP:8080 \
        -o StrictHostKeyChecking=no \
        -o ServerAliveInterval=30 \
        "$INJI_USER@$INJI_SERVER" 2>/dev/null
    sleep 2
    echo -e "  ${GREEN}✓${NC} Forward tunnel: localhost:8080 -> verify-service:8080"

    # Start adapter with upstream verify-service configured
    if [ -f "$ADAPTER_DIR/adapter.js" ]; then
        cd "$ADAPTER_DIR"
        UPSTREAM_VERIFY_SERVICE=http://localhost:8080 ADAPTER_PORT=8085 nohup node adapter.js > /tmp/adapter.log 2>&1 &
        sleep 3

        if curl -s --max-time 3 http://localhost:8085/health | grep -q "ok"; then
            echo -e "  ${GREEN}✓${NC} Adapter started on port 8085"
        else
            echo -e "  ${RED}✗${NC} Adapter failed to start"
            cat /tmp/adapter.log | tail -5
        fi
    else
        echo -e "  ${RED}✗${NC} Adapter not found: $ADAPTER_DIR/adapter.js"
    fi

    # Clear remote port and start reverse tunnel (bound to 0.0.0.0 for Docker access)
    echo -e "  Establishing reverse tunnel to $INJI_SERVER..."
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$INJI_USER@$INJI_SERVER" \
        "fuser -k 8085/tcp 2>/dev/null || true" 2>/dev/null
    sleep 1

    # Use 0.0.0.0 binding so Docker containers can reach the adapter
    ssh -f -N -R 0.0.0.0:8085:localhost:8085 \
        -o StrictHostKeyChecking=no \
        -o ServerAliveInterval=30 \
        -o ServerAliveCountMax=3 \
        -o ExitOnForwardFailure=yes \
        "$INJI_USER@$INJI_SERVER" 2>/dev/null

    sleep 2

    # Verify tunnel from Docker's perspective (172.17.0.1 is Docker host)
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$INJI_USER@$INJI_SERVER" \
        "curl -s --max-time 3 http://172.17.0.1:8085/health" 2>/dev/null | grep -q "ok"; then
        echo -e "  ${GREEN}✓${NC} Adapter tunnel established (accessible from Docker)"
    elif ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$INJI_USER@$INJI_SERVER" \
        "curl -s --max-time 3 http://localhost:8085/health" 2>/dev/null | grep -q "ok"; then
        echo -e "  ${GREEN}✓${NC} Adapter tunnel established to $INJI_SERVER"
        echo -e "  ${YELLOW}⚠${NC} Note: Tunnel bound to localhost only (GatewayPorts may need enabling)"
    else
        echo -e "  ${YELLOW}⚠${NC} Could not verify adapter tunnel"
    fi
    echo ""
fi

# Step 6: Start testa-agent
echo -e "${YELLOW}━━━ Step 6: Starting Testa Agent ━━━${NC}"

if [ -f "$AGENT_CONFIG" ]; then
    docker run -d \
        --name testa-agent \
        --network docker-deployment_default \
        -p 9004:9004 \
        -p 8004:8004 \
        -e CONNECT_TIMEOUT=10 \
        -e MAX_CONNECTIONS=1000 \
        -e IDLE_TIMEOUT=30000 \
        -e AFJ_REST_LOG_LEVEL=2 \
        -v "$AGENT_CONFIG:/config.json:ro" \
        ghcr.io/credebl/credo-controller:latest \
        --auto-accept-connections --config /config.json \
        > /dev/null 2>&1

    sleep 5

    if docker ps | grep -q testa-agent; then
        echo -e "  ${GREEN}✓${NC} Testa agent started"
        # Check logs for errors
        if docker logs testa-agent 2>&1 | grep -q "Successfully started server"; then
            echo -e "  ${GREEN}✓${NC} Agent API ready on port 8004"
        fi
    else
        echo -e "  ${RED}✗${NC} Testa agent failed to start"
        docker logs testa-agent 2>&1 | tail -5
    fi
else
    echo -e "  ${RED}✗${NC} Agent config not found"
fi
echo ""

# Summary
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    Network Switch Complete                     ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}Current IP:${NC}        $CURRENT_IP"
[ -f "$TUNNEL_URL_FILE" ] && echo -e "  ${CYAN}Agent Tunnel:${NC}      $(cat "$TUNNEL_URL_FILE")"
echo -e "  ${CYAN}Adapter:${NC}           http://localhost:8085"
echo -e "  ${CYAN}Inji Verify:${NC}       http://$INJI_SERVER:3000"
echo ""
echo -e "Commands:"
echo -e "  ${CYAN}Check status:${NC}      $0 --status"
echo -e "  ${CYAN}Issue credential:${NC}  ./patches/polygon-did-fix/issue-employment-credential.sh"
echo -e "  ${CYAN}View logs:${NC}         docker logs -f testa-agent"
echo ""
