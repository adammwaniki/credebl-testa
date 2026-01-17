#!/bin/bash
#
# check-environment.sh
#
# Verifies all required components are installed and running for
# W3C credential issuance and Inji Verify integration.
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; }
warn() { echo -e "${YELLOW}!${NC} $1"; }

echo "============================================"
echo "  Environment Check"
echo "============================================"
echo ""

ERRORS=0

# Check Docker
echo "Checking Docker..."
if docker ps &>/dev/null; then
    pass "Docker is running"
else
    fail "Docker is not running or not installed"
    ((ERRORS++))
fi

# Check PostgreSQL
echo ""
echo "Checking PostgreSQL..."
if docker ps | grep -q postgres; then
    pass "PostgreSQL container is running"
else
    warn "PostgreSQL container not found"
    echo "    Run: docker run -d --name credebl-postgres -e POSTGRES_PASSWORD=postgres -p 5433:5432 postgres:13"
fi

# Check credo-controller Agent
echo ""
echo "Checking credo-controller Agent..."
if docker ps | grep -q credo; then
    pass "credo-controller container is running"

    # Test agent API
    if curl -s --max-time 5 http://localhost:8003/agent &>/dev/null; then
        pass "Agent API is accessible on port 8003"
    else
        fail "Agent API not responding on port 8003"
        ((ERRORS++))
    fi
else
    warn "credo-controller container not found"
fi

# Check Node.js
echo ""
echo "Checking Node.js..."
if command -v node &>/dev/null; then
    NODE_VERSION=$(node -v)
    pass "Node.js installed: $NODE_VERSION"
else
    fail "Node.js is not installed"
    ((ERRORS++))
fi

# Check npm
if command -v npm &>/dev/null; then
    pass "npm is installed"
else
    fail "npm is not installed"
    ((ERRORS++))
fi

# Check PixelPass
echo ""
echo "Checking PixelPass..."
if node -e "require('@injistack/pixelpass')" 2>/dev/null; then
    pass "@injistack/pixelpass is installed"
else
    warn "@injistack/pixelpass not found"
    echo "    Run: npm install @injistack/pixelpass"
fi

# Check qrencode
echo ""
echo "Checking qrencode..."
if command -v qrencode &>/dev/null; then
    pass "qrencode is installed"
else
    fail "qrencode is not installed"
    echo "    Run: sudo apt install qrencode"
    ((ERRORS++))
fi

# Check curl and jq
echo ""
echo "Checking utilities..."
command -v curl &>/dev/null && pass "curl is installed" || { fail "curl not installed"; ((ERRORS++)); }
command -v jq &>/dev/null && pass "jq is installed" || { fail "jq not installed"; ((ERRORS++)); }

# Check SSH tunnel
echo ""
echo "Checking SSH tunnel..."
if pgrep -f "ssh.*localhost.run" &>/dev/null; then
    pass "SSH tunnel appears to be running"
else
    warn "No active SSH tunnel detected"
    echo "    Run: ssh -R 80:localhost:9003 localhost.run"
fi

# Check Inji Verify (if on same machine)
echo ""
echo "Checking Inji Verify (optional)..."
if docker ps | grep -q verify; then
    pass "Inji Verify containers are running"

    if curl -s --max-time 5 http://localhost:3000 &>/dev/null; then
        pass "Inji Verify UI is accessible on port 3000"
    else
        warn "Inji Verify UI not responding"
    fi
else
    warn "Inji Verify not found (may be on separate server)"
fi

# Summary
echo ""
echo "============================================"
if [[ $ERRORS -eq 0 ]]; then
    echo -e "${GREEN}  All critical checks passed!${NC}"
else
    echo -e "${RED}  $ERRORS critical issue(s) found${NC}"
fi
echo "============================================"

exit $ERRORS
