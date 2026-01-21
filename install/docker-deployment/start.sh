#!/bin/bash
#
# CREDEBL + Inji Verify Startup Script
#
# This script handles the full startup sequence:
# 1. Starts all docker-compose services
# 2. Waits for critical services to be healthy
# 3. Restarts any existing CREDEBL agent containers
#
# Usage: ./start.sh [options]
#   --clean    Remove volumes and start fresh
#   --logs     Follow logs after startup
#
#For EC2 Deployment, you'll only need to update these external-facing URLs in .env:                                                                          
#  API_ENDPOINT=<EC2_PUBLIC_IP>:5001                                                                                                                           
#  FRONT_END_URL=http://<EC2_PUBLIC_IP>:3000                                                                                                                   
#  SOCKET_HOST=ws://<EC2_PUBLIC_IP>:5001                                                                                                                       
#  PUBLIC_LOCALHOST_URL=http://<EC2_PUBLIC_IP>:5001                                                                                                            
#  ENABLE_CORS_IP_LIST=http://<EC2_PUBLIC_IP>:3000,...                                                                                                         
#  NEXTAUTH_URL=http://<EC2_PUBLIC_IP>:3000                                                                                                                    
#  NEXTAUTH_COOKIE_DOMAIN=<EC2_PUBLIC_IP>                                                                                                                      
#                                                                                                                                                              
#  The internal services (NATS, Redis, Postgres, Inji Verify) will automatically communicate via Docker DNS - no IP changes needed. 

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Parse arguments
CLEAN=false
FOLLOW_LOGS=false
for arg in "$@"; do
    case $arg in
        --clean)
            CLEAN=true
            ;;
        --logs)
            FOLLOW_LOGS=true
            ;;
    esac
done

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║           CREDEBL + Inji Verify Startup                        ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Clean start if requested
if [ "$CLEAN" = true ]; then
    echo -e "${YELLOW}[1/5] Cleaning up (removing volumes)...${NC}"
    docker compose down -v 2>/dev/null || true
else
    echo -e "${YELLOW}[1/5] Stopping existing containers...${NC}"
    docker compose down 2>/dev/null || true
fi

# Start all services
echo -e "${YELLOW}[2/5] Starting docker-compose services...${NC}"
docker compose up -d

# Wait for postgres to be healthy
echo -e "${YELLOW}[3/5] Waiting for databases to be healthy...${NC}"
echo -n "  CREDEBL Postgres: "
until docker exec credebl-postgres pg_isready -U postgres > /dev/null 2>&1; do
    echo -n "."
    sleep 2
done
echo -e " ${GREEN}ready${NC}"

echo -n "  Inji Verify Postgres: "
until docker exec inji-verify-postgres pg_isready -U postgres > /dev/null 2>&1; do
    echo -n "."
    sleep 2
done
echo -e " ${GREEN}ready${NC}"

# Wait for key services
echo -e "${YELLOW}[4/5] Waiting for services to be healthy...${NC}"

echo -n "  Inji Verify Service: "
for i in {1..60}; do
    if curl -sf http://localhost:8082/v1/verify/actuator/health > /dev/null 2>&1; then
        echo -e " ${GREEN}healthy${NC}"
        break
    fi
    echo -n "."
    sleep 2
    if [ $i -eq 60 ]; then
        echo -e " ${YELLOW}timeout (may still be starting)${NC}"
    fi
done

echo -n "  Verification Adapter: "
for i in {1..30}; do
    if curl -sf http://localhost:8085/health > /dev/null 2>&1; then
        echo -e " ${GREEN}healthy${NC}"
        break
    fi
    echo -n "."
    sleep 2
    if [ $i -eq 30 ]; then
        echo -e " ${YELLOW}timeout${NC}"
    fi
done

echo -n "  API Gateway: "
for i in {1..30}; do
    if curl -sf http://localhost:5001/health > /dev/null 2>&1; then
        echo -e " ${GREEN}healthy${NC}"
        break
    fi
    echo -n "."
    sleep 2
    if [ $i -eq 30 ]; then
        echo -e " ${YELLOW}timeout (may still be starting)${NC}"
    fi
done

# Restart any existing CREDEBL agent containers (running or exited)
echo -e "${YELLOW}[5/5] Starting CREDEBL agent containers...${NC}"
AGENT_CONTAINERS=$(docker ps -a --filter "name=-agent" --format "{{.Names}}" | grep -v "agent-service\|agent-provisioning" || true)

if [ -n "$AGENT_CONTAINERS" ]; then
    for agent in $AGENT_CONTAINERS; do
        # Check current state
        STATE=$(docker inspect -f '{{.State.Status}}' "$agent" 2>/dev/null || echo "unknown")
        echo -n "  Starting $agent (was $STATE): "

        # Try to start - if it fails due to network issues, reconnect and retry
        if ! docker start "$agent" > /dev/null 2>&1; then
            # Likely a stale network reference - reconnect to current network
            docker network disconnect docker-deployment_default "$agent" 2>/dev/null || true
            docker network connect docker-deployment_default "$agent" 2>/dev/null || true
            docker start "$agent" > /dev/null 2>&1
        fi

        sleep 3
        if docker ps --filter "name=$agent" --filter "status=running" -q | grep -q .; then
            echo -e "${GREEN}done${NC}"
        else
            echo -e "${RED}failed${NC}"
        fi
    done
else
    echo -e "  ${CYAN}No agent containers found (provision one via API)${NC}"
fi

# Summary
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    Startup Complete!                           ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}Services:${NC}"
echo -e "    CREDEBL API Gateway:    http://localhost:5001"
echo -e "    Verification Adapter:   http://localhost:8085"
echo -e "    Inji Verify UI:         http://localhost:3001"
echo -e "    Inji Verify API:        http://localhost:8082"
echo ""
echo -e "  ${CYAN}Verification endpoint (all credential types):${NC}"
echo -e "    POST http://localhost:8085/v1/verify/vc-verification"
echo ""

# Show container status
echo -e "  ${CYAN}Container Status:${NC}"
docker ps --format "    {{.Names}}: {{.Status}}" | grep -E "inji-verify|verification-adapter|api-gateway|credebl-postgres" | head -10

echo ""
echo -e "  ${CYAN}Notes:${NC}"
echo -e "    - Internal services use Docker DNS (service discovery)"
echo -e "    - External URLs (API_ENDPOINT, FRONT_END_URL) need manual config"
echo ""

# Follow logs if requested
if [ "$FOLLOW_LOGS" = true ]; then
    echo -e "${CYAN}Following logs (Ctrl+C to stop)...${NC}"
    docker compose logs -f verification-adapter inji-verify-service
fi
