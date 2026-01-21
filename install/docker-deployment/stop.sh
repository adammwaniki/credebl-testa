#!/bin/bash
#
# CREDEBL + Inji Verify Stop Script
#
# Usage: ./stop.sh [options]
#   --clean    Also remove volumes (data will be lost)
#   --all      Also stop CREDEBL agent containers
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

CLEAN=false
STOP_AGENTS=false
for arg in "$@"; do
    case $arg in
        --clean)
            CLEAN=true
            ;;
        --all)
            STOP_AGENTS=true
            ;;
    esac
done

echo ""
echo -e "${CYAN}Stopping CREDEBL + Inji Verify...${NC}"
echo ""

# Stop agent containers if requested
if [ "$STOP_AGENTS" = true ]; then
    echo -e "${YELLOW}Stopping CREDEBL agent containers...${NC}"
    AGENT_CONTAINERS=$(docker ps --filter "name=-agent" --format "{{.Names}}" | grep -v "agent-service\|agent-provisioning" || true)
    if [ -n "$AGENT_CONTAINERS" ]; then
        for agent in $AGENT_CONTAINERS; do
            echo "  Stopping $agent..."
            docker stop "$agent" > /dev/null 2>&1 || true
        done
    fi
fi

# Stop docker-compose services
if [ "$CLEAN" = true ]; then
    echo -e "${YELLOW}Stopping and removing volumes...${NC}"
    docker compose down -v
    echo -e "${RED}Warning: All data has been removed${NC}"
else
    echo -e "${YELLOW}Stopping services (data preserved)...${NC}"
    docker compose down
fi

echo ""
echo -e "${GREEN}Stopped.${NC}"
echo ""
