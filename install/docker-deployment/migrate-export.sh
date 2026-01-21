#!/bin/bash
#
# CREDEBL Migration Export Script
#
# This script exports all data needed to migrate CREDEBL to a new server (e.g., EC2).
# Run this on your LOCAL machine to create a migration package.
#
# Usage: ./migrate-export.sh [output_directory]
#
# What gets exported:
#   - PostgreSQL database dump (all databases including wallets)
#   - Agent configuration files
#   - Environment files
#   - Docker compose and related configs
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Output directory
OUTPUT_DIR="${1:-./migration-package}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
PACKAGE_NAME="credebl-migration-${TIMESTAMP}"
PACKAGE_DIR="${OUTPUT_DIR}/${PACKAGE_NAME}"

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║           CREDEBL Migration Export                             ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if containers are running
if ! docker ps | grep -q credebl-postgres; then
    echo -e "${RED}Error: credebl-postgres container is not running${NC}"
    echo "Please start the services first: ./start.sh"
    exit 1
fi

# Create package directory
echo -e "${YELLOW}[1/5] Creating migration package directory...${NC}"
mkdir -p "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR/agent-config"
mkdir -p "$PACKAGE_DIR/patches"

# Export PostgreSQL databases
echo -e "${YELLOW}[2/5] Exporting PostgreSQL databases...${NC}"
echo "  This includes all wallet data, credentials, and platform data..."

docker exec credebl-postgres pg_dumpall -U postgres > "$PACKAGE_DIR/credebl-full-backup.sql"
echo -e "  ${GREEN}Exported: credebl-full-backup.sql${NC}"

# Also export individual databases for flexibility
echo "  Exporting individual databases..."
for db in credebl TestaIssuer002Wallet platform-admin; do
    if docker exec credebl-postgres psql -U postgres -lqt | cut -d \| -f 1 | grep -qw "$db"; then
        docker exec credebl-postgres pg_dump -U postgres "$db" > "$PACKAGE_DIR/${db}-backup.sql"
        echo -e "    ${GREEN}Exported: ${db}-backup.sql${NC}"
    fi
done

# Copy agent configuration files
echo -e "${YELLOW}[3/5] Copying agent configuration files...${NC}"
if [ -d "apps/agent-provisioning/AFJ/agent-config" ]; then
    cp -r apps/agent-provisioning/AFJ/agent-config/* "$PACKAGE_DIR/agent-config/" 2>/dev/null || true
    echo -e "  ${GREEN}Copied agent configs${NC}"

    # List what was copied
    for f in "$PACKAGE_DIR/agent-config"/*.json; do
        [ -f "$f" ] && echo "    - $(basename "$f")"
    done
fi

# Copy environment and config files
echo -e "${YELLOW}[4/5] Copying environment and configuration files...${NC}"

# Main .env file
cp .env "$PACKAGE_DIR/env-template" 2>/dev/null || true
echo -e "  ${GREEN}Copied: .env -> env-template${NC}"

# Agent env
cp agent.env "$PACKAGE_DIR/agent-env-template" 2>/dev/null || true
echo -e "  ${GREEN}Copied: agent.env -> agent-env-template${NC}"

# Docker compose
cp docker-compose.yml "$PACKAGE_DIR/"
echo -e "  ${GREEN}Copied: docker-compose.yml${NC}"

# Start/stop scripts
cp start.sh stop.sh "$PACKAGE_DIR/" 2>/dev/null || true
echo -e "  ${GREEN}Copied: start.sh, stop.sh${NC}"

# Patches directory (only the necessary parts)
mkdir -p "$PACKAGE_DIR/patches/polygon-did-fix"
mkdir -p "$PACKAGE_DIR/patches/inji-verify-official"
cp -r patches/polygon-did-fix/adapter "$PACKAGE_DIR/patches/polygon-did-fix/"
cp -r patches/inji-verify-official/docker-compose "$PACKAGE_DIR/patches/inji-verify-official/"
echo -e "  ${GREEN}Copied: patches/polygon-did-fix/adapter/${NC}"
echo -e "  ${GREEN}Copied: patches/inji-verify-official/docker-compose/${NC}"

# Copy master table
cp credebl-master-table.json "$PACKAGE_DIR/" 2>/dev/null || true

# Create the import script
echo -e "${YELLOW}[5/5] Creating import script for EC2...${NC}"

cat > "$PACKAGE_DIR/migrate-import.sh" << 'IMPORT_SCRIPT'
#!/bin/bash
#
# CREDEBL Migration Import Script
#
# Run this on your EC2 instance to import the migration package.
#
# Usage: ./migrate-import.sh <EC2_PUBLIC_IP_OR_DOMAIN> [AGENT_ENDPOINT_URL]
#
# Example:
#   ./migrate-import.sh 54.123.45.67
#   ./migrate-import.sh ec2.example.com https://ec2.example.com
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

if [ -z "$1" ]; then
    echo -e "${RED}Error: Please provide EC2 public IP or domain${NC}"
    echo "Usage: $0 <EC2_PUBLIC_IP_OR_DOMAIN> [AGENT_ENDPOINT_URL]"
    echo ""
    echo "Example:"
    echo "  $0 54.123.45.67"
    echo "  $0 ec2.example.com https://ec2.example.com"
    exit 1
fi

EC2_HOST="$1"
AGENT_ENDPOINT="${2:-http://${EC2_HOST}:9004}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║           CREDEBL Migration Import                             ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  EC2 Host: ${GREEN}${EC2_HOST}${NC}"
echo -e "  Agent Endpoint: ${GREEN}${AGENT_ENDPOINT}${NC}"
echo ""

# Step 1: Update environment file
echo -e "${YELLOW}[1/6] Updating environment file...${NC}"

if [ -f "env-template" ]; then
    cp env-template .env

    # Replace old IP with new EC2 host
    # Common patterns to replace
    sed -i "s|192\.168\.[0-9]\+\.[0-9]\+|${EC2_HOST}|g" .env
    sed -i "s|API_ENDPOINT=.*|API_ENDPOINT=${EC2_HOST}:5001|" .env
    sed -i "s|FRONT_END_URL=.*|FRONT_END_URL=http://${EC2_HOST}:3000|" .env
    sed -i "s|SOCKET_HOST=.*|SOCKET_HOST=ws://${EC2_HOST}:5001|" .env
    sed -i "s|PUBLIC_LOCALHOST_URL=.*|PUBLIC_LOCALHOST_URL=http://${EC2_HOST}:5001|" .env
    sed -i "s|NEXTAUTH_URL=.*|NEXTAUTH_URL=http://${EC2_HOST}:3000|" .env
    sed -i "s|NEXTAUTH_COOKIE_DOMAIN=.*|NEXTAUTH_COOKIE_DOMAIN=${EC2_HOST}|" .env

    echo -e "  ${GREEN}Updated .env with EC2 host${NC}"
fi

if [ -f "agent-env-template" ]; then
    cp agent-env-template agent.env
    sed -i "s|192\.168\.[0-9]\+\.[0-9]\+|${EC2_HOST}|g" agent.env
    echo -e "  ${GREEN}Updated agent.env${NC}"
fi

# Step 2: Update agent configuration files
echo -e "${YELLOW}[2/6] Updating agent configuration files...${NC}"

mkdir -p apps/agent-provisioning/AFJ/agent-config

for config_file in agent-config/*.json; do
    if [ -f "$config_file" ]; then
        filename=$(basename "$config_file")
        dest="apps/agent-provisioning/AFJ/agent-config/$filename"

        cp "$config_file" "$dest"

        # Update hardcoded IPs to use Docker DNS for internal services
        # walletUrl should point to credebl-postgres (internal Docker DNS)
        sed -i 's|"walletUrl": "[^"]*"|"walletUrl": "credebl-postgres:5432"|' "$dest"

        # webhookUrl should use the EC2 host (external)
        sed -i "s|\"webhookUrl\": \"[^\"]*\"|\"webhookUrl\": \"http://${EC2_HOST}:5000/wh/\"|" "$dest"

        # Fix webhookUrl to include the agent ID
        AGENT_ID=$(echo "$filename" | sed 's/_.*$//')
        sed -i "s|/wh/\"|/wh/${AGENT_ID}\"|" "$dest"

        # schemaFileServerURL should use Docker DNS (internal)
        sed -i 's|"schemaFileServerURL": "[^"]*"|"schemaFileServerURL": "http://schema-file-server:4001/schemas/"|' "$dest"

        # endpoint should be the public agent endpoint
        sed -i "s|\"endpoint\": \[[^]]*\]|\"endpoint\": [\"${AGENT_ENDPOINT}\"]|" "$dest"

        echo -e "  ${GREEN}Updated: $filename${NC}"
    fi
done

# Step 3: Setup directory structure
echo -e "${YELLOW}[3/6] Setting up directory structure...${NC}"

mkdir -p apps/uploadedFiles/exports
mkdir -p apps/agent-provisioning/AFJ/token
mkdir -p apps/schemas

echo -e "  ${GREEN}Created required directories${NC}"

# Step 4: Start infrastructure services first
echo -e "${YELLOW}[4/6] Starting infrastructure services...${NC}"

docker compose up -d credebl-postgres credebl-nats credebl-redis
echo "  Waiting for PostgreSQL to be ready..."
sleep 10

until docker exec credebl-postgres pg_isready -U postgres > /dev/null 2>&1; do
    echo -n "."
    sleep 2
done
echo -e " ${GREEN}ready${NC}"

# Step 5: Import database
echo -e "${YELLOW}[5/6] Importing database...${NC}"

if [ -f "credebl-full-backup.sql" ]; then
    echo "  Importing full database backup..."
    docker exec -i credebl-postgres psql -U postgres < credebl-full-backup.sql 2>/dev/null || true
    echo -e "  ${GREEN}Database imported${NC}"
else
    echo -e "  ${YELLOW}No database backup found, starting fresh${NC}"
fi

# Step 6: Start all services
echo -e "${YELLOW}[6/6] Starting all services...${NC}"

./start.sh

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           Migration Complete!                                  ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}Services:${NC}"
echo -e "    CREDEBL API Gateway:    http://${EC2_HOST}:5001"
echo -e "    Verification Adapter:   http://${EC2_HOST}:8085"
echo -e "    Inji Verify UI:         http://${EC2_HOST}:3001"
echo ""
echo -e "  ${CYAN}Next Steps:${NC}"
echo -e "    1. Verify services are healthy: docker ps"
echo -e "    2. Check agent status: docker logs testa-agent (or your agent name)"
echo -e "    3. Test verification endpoint: curl http://${EC2_HOST}:8085/health"
echo ""
echo -e "  ${YELLOW}Note:${NC} If agents don't start automatically, you may need to"
echo -e "        re-provision them through the CREDEBL API."
echo ""
IMPORT_SCRIPT

chmod +x "$PACKAGE_DIR/migrate-import.sh"
echo -e "  ${GREEN}Created: migrate-import.sh${NC}"

# Create a README
cat > "$PACKAGE_DIR/README.md" << 'README'
# CREDEBL Migration Package

This package contains everything needed to migrate your CREDEBL instance to a new server.

## Contents

- `credebl-full-backup.sql` - Full PostgreSQL database dump (includes wallet data)
- `agent-config/` - Agent configuration files
- `env-template` - Environment file template
- `docker-compose.yml` - Docker compose configuration
- `start.sh`, `stop.sh` - Service management scripts
- `patches/` - Adapter and Inji Verify configurations
- `migrate-import.sh` - Import script for the new server

## Migration Steps

### On your new EC2 instance:

1. **Prerequisites:**
   ```bash
   # Install Docker and Docker Compose
   sudo apt update
   sudo apt install -y docker.io docker-compose-v2
   sudo usermod -aG docker $USER
   # Log out and back in for group changes
   ```

2. **Copy this package to EC2:**
   ```bash
   scp -r credebl-migration-*.tar.gz ec2-user@<EC2_IP>:~/
   ```

3. **Extract and run import:**
   ```bash
   tar -xzf credebl-migration-*.tar.gz
   cd credebl-migration-*
   ./migrate-import.sh <EC2_PUBLIC_IP>
   ```

4. **For HTTPS with a domain:**
   ```bash
   ./migrate-import.sh yourdomain.com https://yourdomain.com
   ```

## Important Notes

- **Wallet Keys**: The wallet encryption keys are stored in the agent config files.
  These are preserved during migration.

- **Private Keys**: The actual cryptographic private keys (for DIDs, signing) are
  stored in the PostgreSQL database and are included in the backup.

- **Agent Endpoints**: If you were using a tunnel (like ngrok/localtunnel), you'll
  need to update the agent endpoint to your EC2's public URL or set up a new tunnel.

- **Firewall**: Make sure these ports are open on EC2:
  - 5001 - API Gateway
  - 8085 - Verification Adapter
  - 3001 - Inji Verify UI
  - 8004 - Agent Admin API
  - 9004 - Agent Inbound (for connections)

## Troubleshooting

If agents don't start:
```bash
# Check agent logs
docker logs <agent-name>

# Restart agent
docker restart <agent-name>

# If network issues, reconnect to network
docker network connect docker-deployment_default <agent-name>
docker start <agent-name>
```
README

# Create tarball
echo ""
echo -e "${CYAN}Creating compressed archive...${NC}"
cd "$OUTPUT_DIR"
tar -czf "${PACKAGE_NAME}.tar.gz" "$PACKAGE_NAME"

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           Export Complete!                                     ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}Package created:${NC}"
echo -e "    ${OUTPUT_DIR}/${PACKAGE_NAME}.tar.gz"
echo ""
echo -e "  ${CYAN}Package size:${NC}"
ls -lh "${PACKAGE_NAME}.tar.gz" | awk '{print "    " $5}'
echo ""
echo -e "  ${CYAN}Next steps:${NC}"
echo -e "    1. Copy to EC2: scp ${PACKAGE_NAME}.tar.gz user@ec2-ip:~/"
echo -e "    2. On EC2: tar -xzf ${PACKAGE_NAME}.tar.gz"
echo -e "    3. On EC2: cd ${PACKAGE_NAME} && ./migrate-import.sh <EC2_IP>"
echo ""
