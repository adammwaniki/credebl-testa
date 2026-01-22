#!/bin/bash
#
# =============================================================================
# OFFLINE VERIFICATION WORKFLOW DEMO
# =============================================================================
#
# This script demonstrates the offline credential verification workflow.
# It shows how credentials can be verified without internet connectivity
# by using pre-cached issuer information.
#
# WORKFLOW OVERVIEW:
# 1. Check adapter health and connectivity status
# 2. View currently cached issuers
# 3. Sync a new issuer to cache (while online)
# 4. Verify a credential using offline mode
# 5. Test verification through the Inji Verify UI endpoint
#
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Configuration
ADAPTER_URL="${ADAPTER_URL:-http://localhost:8085}"
UI_URL="${UI_URL:-http://localhost:3001}"

# Sample credential for testing (did:web with Ed25519Signature2020)
SAMPLE_CREDENTIAL='{
  "@context": [
    "https://www.w3.org/2018/credentials/v1",
    "https://mosip.github.io/inji-config/contexts/tan-context.json",
    "https://w3id.org/security/suites/ed25519-2020/v1"
  ],
  "id": "https://mosip.io/credential/03e899ae-dcb1-4338-a01f-6802f118e31c",
  "type": ["VerifiableCredential", "IncomeTaxAccountCredential"],
  "issuer": "did:web:mosip.github.io:inji-config:collab:tan",
  "issuanceDate": "2025-04-04T12:02:23.099Z",
  "expirationDate": "2027-04-04T12:02:23.099Z",
  "credentialSubject": {
    "id": "did:jwk:eyJrdHkiOiJSU0EiLCJlIjoiQVFBQiJ9",
    "tan": "314937391853",
    "fullName": "Antony Muriithi",
    "gender": "Male",
    "dateOfBirth": "1994/12/08",
    "email": "antony@cdpi.dev"
  },
  "proof": {
    "type": "Ed25519Signature2020",
    "created": "2025-04-04T12:02:23Z",
    "proofPurpose": "assertionMethod",
    "verificationMethod": "did:web:mosip.github.io:inji-config:collab:tan#key-0",
    "proofValue": "z42jdokizBEhFKTrDfScDckbMa3HL4MZbmQuNS9gLDmKQfuSaGTRX4PEsEbNFwT1xW6SiDxPGAED9nJWpXDKaadLp"
  }
}'

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

print_header() {
    echo ""
    echo -e "${BLUE}=============================================================================${NC}"
    echo -e "${BOLD}${CYAN}  $1${NC}"
    echo -e "${BLUE}=============================================================================${NC}"
    echo ""
}

print_step() {
    echo -e "${YELLOW}>>> ${BOLD}$1${NC}"
}

print_endpoint() {
    echo -e "${CYAN}    Endpoint: ${BOLD}$1${NC}"
}

print_success() {
    echo -e "${GREEN}    ✓ $1${NC}"
}

print_error() {
    echo -e "${RED}    ✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}    ℹ $1${NC}"
}

wait_for_user() {
    echo ""
    echo -e "${YELLOW}Press Enter to continue...${NC}"
    read -r
}

# =============================================================================
# MAIN WORKFLOW
# =============================================================================

clear
print_header "OFFLINE VERIFICATION WORKFLOW DEMO"

echo "This demo shows how the verification adapter enables offline credential"
echo "verification by caching issuer DID documents and public keys."
echo ""
echo "Configuration:"
echo "  - Adapter URL: $ADAPTER_URL"
echo "  - UI URL: $UI_URL"
echo ""

wait_for_user

# -----------------------------------------------------------------------------
# STEP 1: Health Check
# -----------------------------------------------------------------------------

print_header "STEP 1: Check Adapter Health & Connectivity"

print_step "Checking adapter health status..."
print_endpoint "GET $ADAPTER_URL/health"
echo ""

HEALTH_RESPONSE=$(curl -s "$ADAPTER_URL/health")
echo "$HEALTH_RESPONSE" | jq '.' 2>/dev/null || echo "$HEALTH_RESPONSE"

echo ""
CONNECTIVITY=$(echo "$HEALTH_RESPONSE" | jq -r '.connectivity' 2>/dev/null)
if [ "$CONNECTIVITY" == "online" ]; then
    print_success "Adapter is ONLINE - can sync new issuers"
else
    print_info "Adapter is OFFLINE - using cached issuers only"
fi

wait_for_user

# -----------------------------------------------------------------------------
# STEP 2: View Cached Issuers
# -----------------------------------------------------------------------------

print_header "STEP 2: View Currently Cached Issuers"

print_step "Retrieving cached issuer information..."
print_endpoint "GET $ADAPTER_URL/cache"
echo ""
echo "The adapter caches DID documents and public keys for issuers."
echo "These cached entries allow offline verification."
echo ""

CACHE_RESPONSE=$(curl -s "$ADAPTER_URL/cache")
echo "$CACHE_RESPONSE" | jq '.' 2>/dev/null || echo "$CACHE_RESPONSE"

echo ""
ISSUER_COUNT=$(echo "$CACHE_RESPONSE" | jq -r '.totalIssuers' 2>/dev/null)
print_info "Total cached issuers: $ISSUER_COUNT"

wait_for_user

# -----------------------------------------------------------------------------
# STEP 3: Sync Issuer (if online)
# -----------------------------------------------------------------------------

print_header "STEP 3: Sync Issuer to Cache (Requires Online)"

print_step "Syncing issuer: did:web:mosip.github.io:inji-config:collab:tan"
print_endpoint "POST $ADAPTER_URL/sync"
echo ""
echo "This step fetches the issuer's DID document and extracts their public key."
echo "The information is cached locally for future offline verification."
echo ""
echo "Request body:"
echo '  { "did": "did:web:mosip.github.io:inji-config:collab:tan" }'
echo ""

SYNC_RESPONSE=$(curl -s -X POST "$ADAPTER_URL/sync" \
    -H "Content-Type: application/json" \
    -d '{"did": "did:web:mosip.github.io:inji-config:collab:tan"}')

echo "Response:"
echo "$SYNC_RESPONSE" | jq '.' 2>/dev/null || echo "$SYNC_RESPONSE"

echo ""
SYNC_SUCCESS=$(echo "$SYNC_RESPONSE" | jq -r '.results[0].success' 2>/dev/null)
if [ "$SYNC_SUCCESS" == "true" ]; then
    print_success "Issuer synced successfully!"
    KEY_TYPE=$(echo "$SYNC_RESPONSE" | jq -r '.results[0].keyType' 2>/dev/null)
    print_info "Key type: $KEY_TYPE"
else
    print_info "Issuer may already be cached or sync failed"
fi

wait_for_user

# -----------------------------------------------------------------------------
# STEP 4: Force Offline Verification
# -----------------------------------------------------------------------------

print_header "STEP 4: Verify Credential (Forced Offline Mode)"

print_step "Verifying credential using OFFLINE mode..."
print_endpoint "POST $ADAPTER_URL/verify-offline"
echo ""
echo "This endpoint forces offline verification, simulating no internet connectivity."
echo "The adapter will:"
echo "  1. Look up the issuer in the local cache"
echo "  2. Validate the credential structure"
echo "  3. Verify the issuer DID matches the cached entry"
echo ""
echo "Credential being verified:"
echo "  - Issuer: did:web:mosip.github.io:inji-config:collab:tan"
echo "  - Type: IncomeTaxAccountCredential"
echo "  - Proof Type: Ed25519Signature2020"
echo ""

OFFLINE_RESPONSE=$(curl -s -X POST "$ADAPTER_URL/verify-offline" \
    -H "Content-Type: application/json" \
    -d "$SAMPLE_CREDENTIAL")

echo "Response:"
echo "$OFFLINE_RESPONSE" | jq '.' 2>/dev/null || echo "$OFFLINE_RESPONSE"

echo ""
VERIFY_STATUS=$(echo "$OFFLINE_RESPONSE" | jq -r '.verificationStatus' 2>/dev/null)
VERIFY_LEVEL=$(echo "$OFFLINE_RESPONSE" | jq -r '.verificationLevel' 2>/dev/null)
IS_OFFLINE=$(echo "$OFFLINE_RESPONSE" | jq -r '.offline' 2>/dev/null)

if [ "$VERIFY_STATUS" == "SUCCESS" ]; then
    print_success "Credential verified successfully!"
    print_info "Verification level: $VERIFY_LEVEL"
    print_info "Offline mode: $IS_OFFLINE"
else
    print_error "Verification failed: $VERIFY_STATUS"
fi

wait_for_user

# -----------------------------------------------------------------------------
# STEP 5: Auto-Mode Verification
# -----------------------------------------------------------------------------

print_header "STEP 5: Verify Credential (Auto Online/Offline Mode)"

print_step "Verifying credential using AUTO mode..."
print_endpoint "POST $ADAPTER_URL/v1/verify/vc-verification"
echo ""
echo "This is the main verification endpoint used by the Inji Verify UI."
echo "The adapter automatically detects:"
echo "  1. If the credential uses Ed25519Signature2020"
echo "  2. If the issuer is already cached"
echo "  3. Routes to offline mode if both conditions are met"
echo ""
echo "This avoids the w3id.org JSON-LD context fetch issue."
echo ""

AUTO_RESPONSE=$(curl -s -X POST "$ADAPTER_URL/v1/verify/vc-verification" \
    -H "Content-Type: application/json" \
    -d "$SAMPLE_CREDENTIAL")

echo "Response:"
echo "$AUTO_RESPONSE" | jq '.' 2>/dev/null || echo "$AUTO_RESPONSE"

echo ""
AUTO_STATUS=$(echo "$AUTO_RESPONSE" | jq -r '.verificationStatus' 2>/dev/null)
if [ "$AUTO_STATUS" == "SUCCESS" ]; then
    print_success "Credential verified successfully!"
else
    print_error "Verification returned: $AUTO_STATUS"
fi

wait_for_user

# -----------------------------------------------------------------------------
# STEP 6: Test Through UI Proxy
# -----------------------------------------------------------------------------

print_header "STEP 6: Verify Through Inji Verify UI Proxy"

print_step "Testing verification through UI nginx proxy..."
print_endpoint "POST $UI_URL/v1/verify/vc-verification"
echo ""
echo "The Inji Verify UI proxies verification requests through nginx."
echo "This test confirms the full end-to-end flow works."
echo ""
echo "Flow: Browser -> UI (nginx) -> Adapter -> Response"
echo ""

UI_RESPONSE=$(curl -s --max-time 10 -X POST "$UI_URL/v1/verify/vc-verification" \
    -H "Content-Type: application/json" \
    -d "$SAMPLE_CREDENTIAL" 2>/dev/null)

if [ -n "$UI_RESPONSE" ]; then
    echo "Response:"
    echo "$UI_RESPONSE" | jq '.' 2>/dev/null || echo "$UI_RESPONSE"

    echo ""
    UI_STATUS=$(echo "$UI_RESPONSE" | jq -r '.verificationStatus' 2>/dev/null)
    if [ "$UI_STATUS" == "SUCCESS" ]; then
        print_success "UI proxy verification successful!"
    else
        print_error "UI verification returned: $UI_STATUS"
    fi
else
    print_error "Could not reach UI at $UI_URL"
    print_info "Make sure the Inji Verify UI is running"
fi

wait_for_user

# -----------------------------------------------------------------------------
# SUMMARY
# -----------------------------------------------------------------------------

print_header "WORKFLOW SUMMARY"

echo "The offline verification workflow enables credential verification"
echo "in environments with limited or no internet connectivity."
echo ""
echo -e "${BOLD}Key Endpoints:${NC}"
echo ""
echo "  1. GET  /health"
echo "     - Check adapter status and connectivity"
echo ""
echo "  2. GET  /cache"
echo "     - View all cached issuers"
echo ""
echo "  3. POST /sync"
echo "     - Add issuer to cache (requires online)"
echo "     - Body: {\"did\": \"did:web:example.com\"}"
echo ""
echo "  4. POST /verify-offline"
echo "     - Force offline verification"
echo "     - Body: <verifiable credential JSON>"
echo ""
echo "  5. POST /v1/verify/vc-verification"
echo "     - Main verification endpoint (auto online/offline)"
echo "     - Compatible with Inji Verify UI"
echo "     - Body: <verifiable credential JSON>"
echo ""
echo -e "${BOLD}Verification Levels:${NC}"
echo ""
echo "  - CRYPTOGRAPHIC: Full signature verification (online)"
echo "  - TRUSTED_ISSUER: Issuer cached, structure validated (offline)"
echo ""
echo -e "${BOLD}Supported DID Methods:${NC}"
echo ""
echo "  - did:polygon  -> CREDEBL Agent (online)"
echo "  - did:web      -> Cached/Inji Verify"
echo "  - did:key      -> Cached (self-resolving)"
echo ""
echo -e "${GREEN}Demo complete!${NC}"
echo ""
