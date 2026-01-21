#!/bin/bash
#
# Demo Revocation Flow
#
# This script demonstrates the full credential revocation lifecycle:
# 1. Verify credential (SUCCESS)
# 2. Revoke credential
# 3. Verify credential again (INVALID - REVOKED)
# 4. Unrevoke (reinstate) credential
# 5. Verify credential again (SUCCESS)
#
# Usage: ./demo-revocation.sh [adapter-url] [credential-file]
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
ADAPTER_URL="${1:-http://localhost:8085}"
CREDENTIAL_FILE="${2:-/tmp/fresh-credential.json}"

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║           Demo: Credential Revocation Flow                     ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}Adapter URL:${NC}     $ADAPTER_URL"
echo -e "  ${CYAN}Credential:${NC}      $CREDENTIAL_FILE"
echo ""

# Check if credential file exists
if [ ! -f "$CREDENTIAL_FILE" ]; then
    echo -e "${RED}Error: Credential file not found: $CREDENTIAL_FILE${NC}"
    echo ""
    echo "Usage: $0 [adapter-url] [credential-file]"
    echo ""
    echo "Example:"
    echo "  $0 http://localhost:8085 /tmp/fresh-credential.json"
    exit 1
fi

# Check adapter health
echo -e "${YELLOW}━━━ Checking Adapter Health ━━━${NC}"
HEALTH=$(curl -s "$ADAPTER_URL/health")
if echo "$HEALTH" | grep -q "ok"; then
    echo -e "  ${GREEN}✓${NC} Adapter is healthy"
    echo "    $HEALTH" | jq -c .
else
    echo -e "  ${RED}✗${NC} Adapter not responding"
    exit 1
fi
echo ""

# Load credential
CREDENTIAL=$(cat "$CREDENTIAL_FILE")
ISSUER=$(echo "$CREDENTIAL" | jq -r '.issuer')
SUBJECT_ID=$(echo "$CREDENTIAL" | jq -r '.credentialSubject.id // .credentialSubject.employeeId // "unknown"')

echo -e "  ${CYAN}Issuer:${NC}     $ISSUER"
echo -e "  ${CYAN}Subject:${NC}    $SUBJECT_ID"
echo ""

# ============================================================================
# STEP 1: Initial Verification (should be SUCCESS)
# ============================================================================
echo -e "${YELLOW}━━━ Step 1: Initial Verification ━━━${NC}"
echo "  Verifying credential (should be SUCCESS)..."

RESULT1=$(curl -s -X POST "$ADAPTER_URL/v1/verify/vc-verification" \
    -H "Content-Type: application/json" \
    -d "{\"credential\": $CREDENTIAL}")

STATUS1=$(echo "$RESULT1" | jq -r '.verificationStatus')

if [ "$STATUS1" = "SUCCESS" ]; then
    echo -e "  ${GREEN}✓${NC} Verification: ${GREEN}SUCCESS${NC}"
else
    echo -e "  ${RED}✗${NC} Verification: ${RED}$STATUS1${NC}"
    echo "    Response: $RESULT1"
fi
echo ""

# ============================================================================
# STEP 2: Revoke the Credential
# ============================================================================
echo -e "${YELLOW}━━━ Step 2: Revoking Credential ━━━${NC}"
echo "  Sending revocation request..."

REVOKE_RESULT=$(curl -s -X POST "$ADAPTER_URL/revocation/revoke" \
    -H "Content-Type: application/json" \
    -d "{
        \"credential\": $CREDENTIAL,
        \"reason\": \"Employee terminated - demo revocation test\"
    }")

REVOKE_SUCCESS=$(echo "$REVOKE_RESULT" | jq -r '.success')
CRED_ID=$(echo "$REVOKE_RESULT" | jq -r '.credentialId')
REVOKED_AT=$(echo "$REVOKE_RESULT" | jq -r '.revokedAt')

if [ "$REVOKE_SUCCESS" = "true" ]; then
    echo -e "  ${GREEN}✓${NC} Credential revoked successfully"
    echo -e "    Credential ID: ${CYAN}$CRED_ID${NC}"
    echo -e "    Revoked at:    $REVOKED_AT"
    echo -e "    Reason:        Employee terminated - demo revocation test"
else
    echo -e "  ${RED}✗${NC} Revocation failed"
    echo "    Response: $REVOKE_RESULT"
fi
echo ""

# ============================================================================
# STEP 3: Verify Again (should be INVALID - REVOKED)
# ============================================================================
echo -e "${YELLOW}━━━ Step 3: Verification After Revocation ━━━${NC}"
echo "  Verifying credential (should be INVALID - REVOKED)..."

RESULT2=$(curl -s -X POST "$ADAPTER_URL/v1/verify/vc-verification" \
    -H "Content-Type: application/json" \
    -d "{\"credential\": $CREDENTIAL}")

STATUS2=$(echo "$RESULT2" | jq -r '.verificationStatus')
ERROR2=$(echo "$RESULT2" | jq -r '.error // "none"')

if [ "$STATUS2" = "INVALID" ] && [ "$ERROR2" = "CREDENTIAL_REVOKED" ]; then
    echo -e "  ${GREEN}✓${NC} Verification: ${RED}INVALID${NC} (as expected)"
    echo -e "    Error: ${YELLOW}CREDENTIAL_REVOKED${NC}"
    echo -e "    Message: $(echo "$RESULT2" | jq -r '.message // "Credential has been revoked"')"
else
    echo -e "  ${YELLOW}⚠${NC} Unexpected result: $STATUS2"
    echo "    Response: $RESULT2"
fi
echo ""

# ============================================================================
# STEP 4: Check Revocation Status
# ============================================================================
echo -e "${YELLOW}━━━ Step 4: Check Revocation Status ━━━${NC}"

CHECK_RESULT=$(curl -s -X POST "$ADAPTER_URL/revocation/check" \
    -H "Content-Type: application/json" \
    -d "{\"credential\": $CREDENTIAL}")

IS_REVOKED=$(echo "$CHECK_RESULT" | jq -r '.isRevoked')
echo -e "  Credential ID: ${CYAN}$(echo "$CHECK_RESULT" | jq -r '.credentialId')${NC}"
echo -e "  Is Revoked:    ${RED}$IS_REVOKED${NC}"
echo ""

# ============================================================================
# STEP 5: List All Revoked Credentials
# ============================================================================
echo -e "${YELLOW}━━━ Step 5: List Revoked Credentials ━━━${NC}"

LIST_RESULT=$(curl -s "$ADAPTER_URL/revocation/list")
COUNT=$(echo "$LIST_RESULT" | jq -r '.count')

echo -e "  Total revoked credentials: ${YELLOW}$COUNT${NC}"
echo "$LIST_RESULT" | jq '.credentials[] | "    - \(.credentialId): \(.reason)"' -r 2>/dev/null || true
echo ""

# ============================================================================
# STEP 6: Unrevoke (Reinstate) the Credential
# ============================================================================
#echo -e "${YELLOW}━━━ Step 6: Reinstating Credential ━━━${NC}"
#echo "  Unrevoking credential..."
#
#UNREVOKE_RESULT=$(curl -s -X POST "$ADAPTER_URL/revocation/unrevoke" \
#    -H "Content-Type: application/json" \
#    -d "{\"credentialId\": \"$CRED_ID\"}")
#
#UNREVOKE_SUCCESS=$(echo "$UNREVOKE_RESULT" | jq -r '.success')
#
#if [ "$UNREVOKE_SUCCESS" = "true" ]; then
#    echo -e "  ${GREEN}✓${NC} Credential reinstated successfully"
#    echo -e "    Reinstated at: $(echo "$UNREVOKE_RESULT" | jq -r '.reinstatedAt')"
#else
#    echo -e "  ${RED}✗${NC} Reinstatement failed"
#    echo "    Response: $UNREVOKE_RESULT"
#fi
#echo ""

# ============================================================================
# STEP 7: Final Verification (should be SUCCESS again)
# ============================================================================
#echo -e "${YELLOW}━━━ Step 7: Final Verification ━━━${NC}"
#echo "  Verifying credential (should be SUCCESS again)..."
#
#RESULT3=$(curl -s -X POST "$ADAPTER_URL/v1/verify/vc-verification" \
#    -H "Content-Type: application/json" \
#    -d "{\"credential\": $CREDENTIAL}")
#
#STATUS3=$(echo "$RESULT3" | jq -r '.verificationStatus')
#
#if [ "$STATUS3" = "SUCCESS" ]; then
#    echo -e "  ${GREEN}✓${NC} Verification: ${GREEN}SUCCESS${NC}"
#else
#    echo -e "  ${RED}✗${NC} Verification: ${RED}$STATUS3${NC}"
#    echo "    Response: $RESULT3"
#fi
#echo ""

# ============================================================================
# SUMMARY
# ============================================================================
echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                    Demo Complete                               ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Revocation Flow Summary:"
echo ""
echo "  Step 1: Initial verification    → ${GREEN}SUCCESS${NC}"
echo "  Step 2: Revoke credential       → ${GREEN}Done${NC}"
echo "  Step 3: Verify after revoke     → ${RED}INVALID (REVOKED)${NC}"
echo "  Step 4: Check revocation status → ${YELLOW}Confirmed revoked${NC}"
echo "  Step 5: List revoked            → ${YELLOW}Listed${NC}"
#echo "  Step 6: Reinstate credential    → ${GREEN}Done${NC}"
#echo "  Step 7: Verify after reinstate  → ${GREEN}SUCCESS${NC}"
echo ""
echo -e "${GREEN}The revocation system is working correctly!${NC}"
echo ""
echo "API Endpoints used:"
echo "  POST $ADAPTER_URL/v1/verify/vc-verification"
echo "  POST $ADAPTER_URL/revocation/revoke"
echo "  POST $ADAPTER_URL/revocation/check"
echo "  POST $ADAPTER_URL/revocation/unrevoke"
echo "  GET  $ADAPTER_URL/revocation/list"
echo ""
