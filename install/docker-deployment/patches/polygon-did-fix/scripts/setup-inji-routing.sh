#!/bin/bash
#
# Setup script for CREDEBL-Inji Verify integration
# This script configures Inji Verify to route verification requests through the CREDEBL adapter
#
# Usage: ./setup-inji-routing.sh [options]
#
# Prerequisites:
# - Inji Verify running (docker-compose)
# - nginx installed on host
# - CREDEBL adapter accessible (locally or via SSH tunnel)

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADAPTER_PORT="${ADAPTER_PORT:-8085}"
VERIFY_SERVICE_PORT="${VERIFY_SERVICE_PORT:-8082}"
NGINX_PROXY_PORT="${NGINX_PROXY_PORT:-8080}"

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║       CREDEBL-Inji Verify Integration Setup                    ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if running as root or with sudo
check_sudo() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${YELLOW}Note: Some operations may require sudo${NC}"
    fi
}

# Step 1: Check prerequisites
echo -e "${YELLOW}━━━ Step 1: Checking Prerequisites ━━━${NC}"

# Check nginx
if command -v nginx &> /dev/null; then
    echo -e "  ${GREEN}✓${NC} nginx is installed"
else
    echo -e "  ${RED}✗${NC} nginx is not installed"
    echo "    Install with: sudo apt install nginx"
    exit 1
fi

# Check docker
if command -v docker &> /dev/null; then
    echo -e "  ${GREEN}✓${NC} docker is installed"
else
    echo -e "  ${RED}✗${NC} docker is not installed"
    exit 1
fi

# Check if verify-ui container exists
if docker ps -a --format '{{.Names}}' | grep -q "verify-ui"; then
    echo -e "  ${GREEN}✓${NC} verify-ui container found"
else
    echo -e "  ${RED}✗${NC} verify-ui container not found"
    echo "    Make sure Inji Verify is deployed"
    exit 1
fi

# Check adapter connectivity
echo -e "  Checking adapter on port $ADAPTER_PORT..."
if curl -s --max-time 5 "http://localhost:$ADAPTER_PORT/health" | grep -q "ok"; then
    echo -e "  ${GREEN}✓${NC} CREDEBL adapter is accessible"
else
    echo -e "  ${YELLOW}⚠${NC} CREDEBL adapter not accessible on localhost:$ADAPTER_PORT"
    echo "    Make sure the adapter is running or SSH tunnel is established"
fi

echo ""

# Step 2: Configure host nginx
echo -e "${YELLOW}━━━ Step 2: Configuring Host Nginx ━━━${NC}"

NGINX_CONF="/etc/nginx/sites-available/inji-adapter"
NGINX_ENABLED="/etc/nginx/sites-enabled/inji-adapter"

# Create nginx config
sudo tee "$NGINX_CONF" > /dev/null << EOF
server {
    listen $NGINX_PROXY_PORT;
    server_name _;

    location /v1/verify/vc-verification {
        proxy_pass http://localhost:$ADAPTER_PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Content-Type \$http_content_type;
        proxy_connect_timeout 30s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
    }

    location / {
        proxy_pass http://localhost:$VERIFY_SERVICE_PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

echo -e "  ${GREEN}✓${NC} Created nginx config: $NGINX_CONF"

# Enable the site
if [ ! -L "$NGINX_ENABLED" ]; then
    sudo ln -s "$NGINX_CONF" "$NGINX_ENABLED"
    echo -e "  ${GREEN}✓${NC} Enabled nginx site"
else
    echo -e "  ${GREEN}✓${NC} Nginx site already enabled"
fi

# Test and reload nginx
if sudo nginx -t 2>/dev/null; then
    sudo systemctl reload nginx
    echo -e "  ${GREEN}✓${NC} Nginx configuration reloaded"
else
    echo -e "  ${RED}✗${NC} Nginx configuration test failed"
    sudo nginx -t
    exit 1
fi

echo ""

# Step 3: Get Docker network gateway
echo -e "${YELLOW}━━━ Step 3: Detecting Docker Network ━━━${NC}"

# Find the network the verify-ui container is on
DOCKER_NETWORK=$(docker inspect verify-ui --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}' 2>/dev/null | head -1)
if [ -z "$DOCKER_NETWORK" ]; then
    DOCKER_NETWORK="bridge"
fi

echo -e "  Container network: $DOCKER_NETWORK"

# Get gateway IP
GATEWAY_IP=$(docker network inspect "$DOCKER_NETWORK" --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}' 2>/dev/null)
if [ -z "$GATEWAY_IP" ]; then
    GATEWAY_IP="172.17.0.1"  # Default Docker bridge
fi

echo -e "  ${GREEN}✓${NC} Docker gateway IP: $GATEWAY_IP"
echo ""

# Step 4: Configure verify-ui container
echo -e "${YELLOW}━━━ Step 4: Configuring verify-ui Container ━━━${NC}"

# Create the nginx config for verify-ui
VERIFY_UI_CONF=$(cat << EOF
server {
    listen 8000;
    root   /usr/share/nginx/html;
    index  index.html index.htm;

    error_page 500 502 503 504 /50x.html;
    location = /50x.html {
        root /usr/share/nginx/html;
    }

    location /v1/verify {
        proxy_pass http://${GATEWAY_IP}:${NGINX_PROXY_PORT}/v1/verify;
        proxy_redirect     off;
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Host \$server_name;
        proxy_set_header   Connection close;
        proxy_connect_timeout 30s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
    }

    location /.well-known/did.json {
        proxy_pass http://${GATEWAY_IP}:${NGINX_PROXY_PORT}/v1/verify/.well-known/did.json;
        proxy_redirect     off;
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Host \$server_name;
        proxy_set_header   Connection close;
    }

    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
EOF
)

# Write to temp file and copy to container
echo "$VERIFY_UI_CONF" > /tmp/verify-ui-nginx.conf
docker cp /tmp/verify-ui-nginx.conf verify-ui:/etc/nginx/conf.d/default.conf

echo -e "  ${GREEN}✓${NC} Copied nginx config to verify-ui container"

# Reload nginx in container
docker exec verify-ui nginx -s reload 2>/dev/null
echo -e "  ${GREEN}✓${NC} Reloaded nginx in verify-ui container"

rm /tmp/verify-ui-nginx.conf
echo ""

# Step 5: Verify configuration
echo -e "${YELLOW}━━━ Step 5: Verifying Configuration ━━━${NC}"

# Test host nginx
if curl -s --max-time 5 "http://localhost:$NGINX_PROXY_PORT/" > /dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} Host nginx responding on port $NGINX_PROXY_PORT"
else
    echo -e "  ${YELLOW}⚠${NC} Host nginx not responding (verify-service may not be running)"
fi

# Test through verify-ui
UI_PORT=$(docker port verify-ui 8000 2>/dev/null | cut -d: -f2)
if [ -n "$UI_PORT" ]; then
    echo -e "  ${GREEN}✓${NC} verify-ui accessible on port $UI_PORT"
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    Setup Complete!                             ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Configuration summary:"
echo "  - Host nginx proxy:     localhost:$NGINX_PROXY_PORT"
echo "  - Adapter service:      localhost:$ADAPTER_PORT"
echo "  - Verify service:       localhost:$VERIFY_SERVICE_PORT"
echo "  - Docker gateway:       $GATEWAY_IP"
echo ""
echo "Verification requests from Inji Verify UI will now route through"
echo "the CREDEBL adapter for did:polygon credential verification."
echo ""
echo "To test:"
echo "  curl -X POST http://localhost:$NGINX_PROXY_PORT/v1/verify/vc-verification \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"credential\": {...}}'"
echo ""
