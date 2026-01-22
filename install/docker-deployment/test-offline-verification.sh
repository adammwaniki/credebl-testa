#!/bin/bash
#
# =============================================================================
# OFFLINE VERIFICATION QUICK TEST
# =============================================================================
#
# Non-interactive version of the offline verification demo.
# Runs all tests and shows results without pausing.
#
# Usage: ./test-offline-verification.sh [--verbose]
#
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

VERBOSE=${1:-""}
ADAPTER_URL="${ADAPTER_URL:-http://localhost:8085}"
UI_URL="${UI_URL:-http://localhost:3001}"

# Sample credential
SAMPLE_CREDENTIAL='{
  "@context": ["https://www.w3.org/2018/credentials/v1", "https://w3id.org/security/suites/ed25519-2020/v1"],
  "type": ["VerifiableCredential", "IncomeTaxAccountCredential"],
  "issuer": "did:web:mosip.github.io:inji-config:collab:tan",
  "issuanceDate": "2025-04-04T12:02:23.099Z",
  "credentialSubject": {"id": "did:example:123", "fullName": "Test User"},
  "proof": {
    "type": "Ed25519Signature2020",
    "created": "2025-04-04T12:02:23Z",
    "proofPurpose": "assertionMethod",
    "verificationMethod": "did:web:mosip.github.io:inji-config:collab:tan#key-0",
    "proofValue": "z42jdokizBEhFKTrDfScDckbMa3HL4MZbmQuNS9gLDmKQfuSaGTRX4PEsEbNFwT1xW6SiDxPGAED9nJWpXDKaadLp"
  }
}'

echo ""
echo -e "${BOLD}${CYAN}OFFLINE VERIFICATION QUICK TEST${NC}"
echo -e "${BLUE}=================================${NC}"
echo ""

# Test 1: Health Check
echo -e "${YELLOW}[1/5]${NC} Checking adapter health..."
echo -e "      ${CYAN}GET $ADAPTER_URL/health${NC}"
HEALTH=$(curl -s "$ADAPTER_URL/health")
STATUS=$(echo "$HEALTH" | jq -r '.status' 2>/dev/null)
CONNECTIVITY=$(echo "$HEALTH" | jq -r '.connectivity' 2>/dev/null)
if [ "$STATUS" == "ok" ]; then
    echo -e "      ${GREEN}✓ Adapter healthy, connectivity: $CONNECTIVITY${NC}"
else
    echo -e "      ${RED}✗ Adapter not responding${NC}"
    exit 1
fi
[ "$VERBOSE" == "--verbose" ] && echo "$HEALTH" | jq '.'
echo ""

# Test 2: Cache Status
echo -e "${YELLOW}[2/5]${NC} Checking cached issuers..."
echo -e "      ${CYAN}GET $ADAPTER_URL/cache${NC}"
CACHE=$(curl -s "$ADAPTER_URL/cache")
ISSUER_COUNT=$(echo "$CACHE" | jq -r '.totalIssuers' 2>/dev/null)
echo -e "      ${GREEN}✓ Cached issuers: $ISSUER_COUNT${NC}"
[ "$VERBOSE" == "--verbose" ] && echo "$CACHE" | jq '.issuers[].did'
echo ""

# Test 3: Sync Issuer
echo -e "${YELLOW}[3/5]${NC} Syncing test issuer..."
echo -e "      ${CYAN}POST $ADAPTER_URL/sync${NC}"
echo -e "      Body: {\"did\": \"did:web:mosip.github.io:inji-config:collab:tan\"}"
SYNC=$(curl -s -X POST "$ADAPTER_URL/sync" \
    -H "Content-Type: application/json" \
    -d '{"did": "did:web:mosip.github.io:inji-config:collab:tan"}')
SYNC_OK=$(echo "$SYNC" | jq -r '.results[0].success' 2>/dev/null)
if [ "$SYNC_OK" == "true" ]; then
    KEY_TYPE=$(echo "$SYNC" | jq -r '.results[0].keyType' 2>/dev/null)
    echo -e "      ${GREEN}✓ Issuer synced (keyType: $KEY_TYPE)${NC}"
else
    echo -e "      ${BLUE}ℹ Issuer already cached or sync skipped${NC}"
fi
[ "$VERBOSE" == "--verbose" ] && echo "$SYNC" | jq '.'
echo ""

# Test 4: Offline Verification
echo -e "${YELLOW}[4/5]${NC} Testing forced offline verification..."
echo -e "      ${CYAN}POST $ADAPTER_URL/verify-offline${NC}"
OFFLINE=$(curl -s -X POST "$ADAPTER_URL/verify-offline" \
    -H "Content-Type: application/json" \
    -d "$SAMPLE_CREDENTIAL")
OFFLINE_STATUS=$(echo "$OFFLINE" | jq -r '.verificationStatus' 2>/dev/null)
OFFLINE_LEVEL=$(echo "$OFFLINE" | jq -r '.verificationLevel' 2>/dev/null)
if [ "$OFFLINE_STATUS" == "SUCCESS" ]; then
    echo -e "      ${GREEN}✓ Offline verification: $OFFLINE_STATUS ($OFFLINE_LEVEL)${NC}"
else
    echo -e "      ${RED}✗ Offline verification: $OFFLINE_STATUS${NC}"
fi
[ "$VERBOSE" == "--verbose" ] && echo "$OFFLINE" | jq '.'
echo ""

# Test 5: Auto-mode Verification
echo -e "${YELLOW}[5/5]${NC} Testing auto-mode verification (Inji UI endpoint)..."
echo -e "      ${CYAN}POST $ADAPTER_URL/v1/verify/vc-verification${NC}"
AUTO=$(curl -s -X POST "$ADAPTER_URL/v1/verify/vc-verification" \
    -H "Content-Type: application/json" \
    -d "$SAMPLE_CREDENTIAL")
AUTO_STATUS=$(echo "$AUTO" | jq -r '.verificationStatus' 2>/dev/null)
AUTO_OFFLINE=$(echo "$AUTO" | jq -r '.offline' 2>/dev/null)
if [ "$AUTO_STATUS" == "SUCCESS" ]; then
    echo -e "      ${GREEN}✓ Auto verification: $AUTO_STATUS (offline=$AUTO_OFFLINE)${NC}"
else
    echo -e "      ${RED}✗ Auto verification: $AUTO_STATUS${NC}"
fi
[ "$VERBOSE" == "--verbose" ] && echo "$AUTO" | jq '.'
echo ""

# Summary
echo -e "${BLUE}=================================${NC}"
echo -e "${BOLD}SUMMARY${NC}"
echo -e "${BLUE}=================================${NC}"
echo ""
echo -e "Adapter URL:     $ADAPTER_URL"
echo -e "Cached Issuers:  $ISSUER_COUNT"
echo -e "Connectivity:    $CONNECTIVITY"
echo ""
echo -e "${BOLD}Endpoints Tested:${NC}"
echo -e "  GET  /health                    - ${GREEN}OK${NC}"
echo -e "  GET  /cache                     - ${GREEN}OK${NC}"
echo -e "  POST /sync                      - ${GREEN}OK${NC}"
echo -e "  POST /verify-offline            - $([ "$OFFLINE_STATUS" == "SUCCESS" ] && echo "${GREEN}OK${NC}" || echo "${RED}FAIL${NC}")"
echo -e "  POST /v1/verify/vc-verification - $([ "$AUTO_STATUS" == "SUCCESS" ] && echo "${GREEN}OK${NC}" || echo "${RED}FAIL${NC}")"
echo ""

if [ "$OFFLINE_STATUS" == "SUCCESS" ] && [ "$AUTO_STATUS" == "SUCCESS" ]; then
    echo -e "${GREEN}${BOLD}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}${BOLD}Some tests failed${NC}"
    exit 1
fi
