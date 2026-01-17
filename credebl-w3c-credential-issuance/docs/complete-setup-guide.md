# Complete End-to-End Guide: CREDEBL W3C Credential Issuance to Inji Verify

This comprehensive guide covers the entire process from spinning up containers and services to issuing W3C JSON-LD Verifiable Credentials and verifying them with Inji Verify.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Part 1: Infrastructure Setup](#part-1-infrastructure-setup)
3. [Part 2: Agent Setup & Configuration](#part-2-agent-setup--configuration)
4. [Part 3: SSH Tunnel Setup](#part-3-ssh-tunnel-setup)
5. [Part 4: Connection Establishment](#part-4-connection-establishment)
6. [Part 5: Credential Issuance](#part-5-credential-issuance)
7. [Part 6: QR Code Generation](#part-6-qr-code-generation)
8. [Part 7: Inji Verify Setup](#part-7-inji-verify-setup)
9. [Part 8: Verification](#part-8-verification)
10. [Troubleshooting](#troubleshooting)
11. [Quick Reference Scripts](#quick-reference-scripts)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              CREDENTIAL ISSUANCE FLOW                            │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │   CREDEBL    │    │    credo-    │    │  PostgreSQL  │    │    SSH       │  │
│  │   Platform   │───▶│  controller  │───▶│   Database   │    │   Tunnel     │  │
│  │              │    │  (Agent)     │    │              │    │              │  │
│  └──────────────┘    └──────┬───────┘    └──────────────┘    └──────┬───────┘  │
│                             │                                        │          │
│                             │ DIDComm                               │          │
│                             ▼                                        ▼          │
│                      ┌──────────────┐                        ┌──────────────┐  │
│                      │   Mobile     │◀───────────────────────│   Public     │  │
│                      │   Wallet     │      (via tunnel)      │   Endpoint   │  │
│                      │   (Holder)   │                        │              │  │
│                      └──────────────┘                        └──────────────┘  │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                              VERIFICATION FLOW                                   │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐                       │
│  │  Signed VC   │───▶│  PixelPass   │───▶│   QR Code    │                       │
│  │  (JSON-LD)   │    │  Encoder     │    │   (PNG)      │                       │
│  └──────────────┘    └──────────────┘    └──────┬───────┘                       │
│                                                  │                               │
│                                                  ▼                               │
│                                          ┌──────────────┐    ┌──────────────┐   │
│                                          │    Inji      │───▶│   Verify     │   │
│                                          │   Verify     │    │   Service    │   │
│                                          │   (Scanner)  │    │   (Backend)  │   │
│                                          └──────────────┘    └──────────────┘   │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### Components

| Component | Purpose | Port |
|-----------|---------|------|
| credo-controller | Aries agent for credential operations | 8003 (admin), 9003 (DIDComm) |
| PostgreSQL | Wallet storage | 5433 |
| SSH Tunnel | Public endpoint for mobile wallets | 443 (external) → 9003 (internal) |
| Inji Verify UI | Web interface for scanning QR codes | 3000 |
| Inji Verify Service | Backend verification service | 8080 |

---

## Part 1: Infrastructure Setup

### 1.1 Prerequisites

```bash
# Required software
- Docker & Docker Compose
- Node.js (v18+)
- npm
- curl
- jq
- qrencode
```

### 1.2 Start PostgreSQL Database

```bash
# Start PostgreSQL container for wallet storage
docker run -d \
  --name credebl-postgres \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres \
  -p 5433:5432 \
  postgres:13

# Verify it's running
docker ps | grep credebl-postgres
```

### 1.3 Create Agent Configuration

Create the agent configuration file:

```bash
mkdir -p /path/to/agent-config

cat > /path/to/agent-config/agent-config.json << 'EOF'
{
  "label": "YOUR_ORG_ID_YOUR_ORG_NAME",
  "walletId": "DedicatedAgent",
  "walletKey": "AgentPass1234",
  "walletType": "postgres",
  "walletUrl": "YOUR_HOST_IP:5433",
  "walletAccount": "postgres",
  "walletPassword": "postgres",
  "walletAdminAccount": "postgres",
  "walletAdminPassword": "postgres",
  "walletScheme": "DatabasePerWallet",
  "indyLedger": [
    {
      "genesisTransactions": "https://raw.githubusercontent.com/Indicio-tech/indicio-network/main/genesis_files/pool_transactions_demonet_genesis",
      "indyNamespace": "indicio:demonet"
    }
  ],
  "endpoint": ["https://YOUR_TUNNEL_URL"],
  "autoAcceptConnections": true,
  "autoAcceptCredentials": "contentApproved",
  "autoAcceptProofs": "contentApproved",
  "logLevel": 2,
  "inboundTransport": [
    {
      "transport": "http",
      "port": 9003
    }
  ],
  "outboundTransport": ["http"],
  "webhookUrl": "http://YOUR_HOST_IP:5000/wh/YOUR_ORG_ID",
  "adminPort": 8003,
  "tenancy": false,
  "schemaFileServerURL": "http://YOUR_HOST_IP:4001/schemas/",
  "apiKey": "supersecret-that-too-16chars"
}
EOF
```

**Important Configuration Notes:**

- Replace `YOUR_HOST_IP` with your machine's IP address (use `hostname -I | awk '{print $1}'`)
- Replace `YOUR_TUNNEL_URL` with the SSH tunnel URL (set up in Part 3)
- The `apiKey` must be at least 16 characters

### 1.4 Start credo-controller Agent

```bash
docker run -d \
  --name credo-controller-agent \
  -p 8003:8003 \
  -p 9003:9003 \
  -v /path/to/agent-config:/config \
  ghcr.io/credebl/credo-controller:latest \
  --config /config/agent-config.json

# Check if agent is running
docker logs credo-controller-agent --tail 20
```

### 1.5 Verify Agent Status

```bash
# Get JWT token
JWT=$(curl -s -X POST http://localhost:8003/agent/token \
  -H "authorization: supersecret-that-too-16chars" | jq -r '.token')

# Check agent info
curl -s -H "authorization: $JWT" http://localhost:8003/agent | jq .
```

Expected response:
```json
{
  "label": "YOUR_ORG_ID_YOUR_ORG_NAME",
  "endpoints": ["https://YOUR_TUNNEL_URL"],
  "isInitialized": true
}
```

---

## Part 2: Agent Setup & Configuration

### 2.1 Agent Authentication

The credo-controller uses a two-step authentication process:

1. **API Key** → Used to generate a JWT token
2. **JWT Token** → Used for all subsequent API calls

```bash
# Step 1: Get JWT token using API key
JWT=$(curl -s -X POST http://localhost:8003/agent/token \
  -H "authorization: YOUR_API_KEY" | jq -r '.token')

# Step 2: Use JWT for API calls
curl -H "authorization: $JWT" http://localhost:8003/agent
```

### 2.2 Get Agent DIDs

```bash
# List all DIDs
curl -s -H "authorization: $JWT" http://localhost:8003/dids | jq .

# The first DID is typically your issuer DID
ISSUER_DID=$(curl -s -H "authorization: $JWT" http://localhost:8003/dids | jq -r '.[0].did')
echo "Issuer DID: $ISSUER_DID"
```

---

## Part 3: SSH Tunnel Setup

Mobile wallets need a public HTTPS endpoint to communicate with your agent. Use SSH tunneling for development.

### 3.1 Using localhost.run

```bash
# Start SSH tunnel
ssh -R 80:localhost:9003 localhost.run

# The output will show your public URL:
# https://abc123def456.lhr.life
```

### 3.2 Save Tunnel URL Script

```bash
cat > start-tunnel.sh << 'EOF'
#!/bin/bash
# Start SSH tunnel and capture URL

echo "Starting SSH tunnel to localhost:9003..."
ssh -R 80:localhost:9003 localhost.run 2>&1 | tee tunnel.log &

# Wait for URL
sleep 5
TUNNEL_URL=$(grep -oP 'https://[a-z0-9]+\.lhr\.life' tunnel.log | head -1)

if [[ -n "$TUNNEL_URL" ]]; then
    echo "Tunnel URL: $TUNNEL_URL"
    echo "$TUNNEL_URL" > tunnel-url.txt
else
    echo "Failed to get tunnel URL. Check tunnel.log"
fi
EOF

chmod +x start-tunnel.sh
```

### 3.3 Update Agent Configuration

After getting the tunnel URL, update your agent config:

```bash
# Update endpoint in agent config
TUNNEL_URL=$(cat tunnel-url.txt)
jq --arg url "$TUNNEL_URL" '.endpoint = [$url]' agent-config.json > temp.json
mv temp.json agent-config.json

# Restart agent
docker restart credo-controller-agent
```

---

## Part 4: Connection Establishment

### 4.1 Create Out-of-Band Invitation

```bash
# Get fresh token
JWT=$(curl -s -X POST http://localhost:8003/agent/token \
  -H "authorization: YOUR_API_KEY" | jq -r '.token')

# Create OOB invitation
INVITATION_RESPONSE=$(curl -s -X POST http://localhost:8003/didcomm/oob/create-invitation \
  -H "authorization: $JWT" \
  -H "Content-Type: application/json" \
  -d '{
    "label": "CREDEBL Issuer",
    "goalCode": "issue-vc",
    "goal": "Issue Verifiable Credential",
    "handshake": true,
    "handshakeProtocols": [
      "https://didcomm.org/didexchange/1.x",
      "https://didcomm.org/connections/1.x"
    ],
    "autoAcceptConnection": true
  }')

# Extract invitation URL
INVITATION_URL=$(echo "$INVITATION_RESPONSE" | jq -r '.invitationUrl')
echo "Invitation URL: $INVITATION_URL"
```

### 4.2 Generate QR Code for Invitation

```bash
# Generate QR code for mobile wallet to scan
echo "$INVITATION_URL" | qrencode -t ANSIUTF8

# Or save as PNG
echo "$INVITATION_URL" | qrencode -o invitation-qr.png -s 10
```

### 4.3 Accept Connection in Mobile Wallet

1. Open mobile wallet (e.g., Sovio)
2. Scan the invitation QR code
3. Accept the connection request

### 4.4 Verify Connection

```bash
# List connections
curl -s -H "authorization: $JWT" http://localhost:8003/didcomm/connections | jq .

# Find the completed connection
CONNECTION_ID=$(curl -s -H "authorization: $JWT" http://localhost:8003/didcomm/connections \
  | jq -r '.[] | select(.state == "completed") | .id' | head -1)

echo "Connection ID: $CONNECTION_ID"
```

---

## Part 5: Credential Issuance

### 5.1 Prepare Credential Data

```bash
# Get holder DID from connection
HOLDER_DID=$(curl -s -H "authorization: $JWT" \
  http://localhost:8003/didcomm/connections/$CONNECTION_ID | jq -r '.theirDid')

# Set issuance date
ISSUANCE_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Example for Employment Data
EMPLOYER_NAME="Testa Credebl Farms"
JOB_TITLE="Field Service Engineer"
START_DATE="2026-01-01"
```

### 5.2 Issue W3C JSON-LD Credential

```bash
CREDENTIAL_RESPONSE=$(curl -s -X POST http://localhost:8003/didcomm/credentials/create-offer \
  -H "authorization: $JWT" \
  -H "Content-Type: application/json" \
  -d "{
    \"connectionId\": \"$CONNECTION_ID\",
    \"protocolVersion\": \"v2\",
    \"credentialFormats\": {
      \"jsonld\": {
        \"credential\": {
          \"@context\": [
            \"https://www.w3.org/2018/credentials/v1\",
            \"https://www.w3.org/2018/credentials/examples/v1\"
          ],
          \"type\": [\"VerifiableCredential\", \"EmploymentCredential\"],
          \"issuer\": \"$ISSUER_DID\",
          \"issuanceDate\": \"$ISSUANCE_DATE\",
          \"credentialSubject\": {
            \"id\": \"$HOLDER_DID\",
            \"employeeOf\": {
              \"name\": \"$EMPLOYER_NAME\",
              \"position\": \"$JOB_TITLE\",
              \"startDate\": \"$START_DATE\"
            }
          }
        },
        \"options\": {
          \"proofType\": \"Ed25519Signature2018\",
          \"proofPurpose\": \"assertionMethod\"
        }
      }
    },
    \"autoAcceptCredential\": \"always\"
  }")

CREDENTIAL_RECORD_ID=$(echo "$CREDENTIAL_RESPONSE" | jq -r '.id')
echo "Credential Record ID: $CREDENTIAL_RECORD_ID"
```

### 5.3 Monitor Credential Exchange

```bash
# Check status (repeat until "done")
curl -s -H "authorization: $JWT" \
  http://localhost:8003/didcomm/credentials/$CREDENTIAL_RECORD_ID | jq '.state'

# Expected states: offer-sent → request-received → credential-issued → done
```

### 5.4 Accept Credential in Mobile Wallet

1. Open notification in mobile wallet
2. Review credential details
3. Accept the credential

### 5.5 Retrieve Signed Credential

```bash
# Get the signed credential with proof
curl -s -H "authorization: $JWT" \
  http://localhost:8003/didcomm/credentials/$CREDENTIAL_RECORD_ID/form-data \
  | jq '.credential.jsonld' > credential.json

cat credential.json
```

---

## Part 6: QR Code Generation

### 6.1 Install PixelPass

```bash
npm install @injistack/pixelpass
```

### 6.2 Encode Credential with PixelPass

```bash
node -e "
const { generateQRData } = require('@injistack/pixelpass');
const fs = require('fs');
const credential = JSON.parse(fs.readFileSync('credential.json', 'utf8'));
process.stdout.write(generateQRData(JSON.stringify(credential)));
" > qrdata.txt

echo "Encoded data length: $(wc -c < qrdata.txt) characters"
```

### 6.3 Generate QR Code

```bash
# As PNG image
qrencode -o credential-qr.png -s 10 -m 2 < qrdata.txt

# Display in terminal
qrencode -t ANSIUTF8 < qrdata.txt
```

### 6.4 Using the Automated Script

```bash
# Use the provided script for the full process
./scripts/issue-and-generate-qr.sh $CONNECTION_ID --api-key YOUR_API_KEY
```

---

## Part 7: Inji Verify Setup

### 7.1 Deploy Inji Verify

```bash
# Clone Inji Verify
git clone https://github.com/mosip/inji-verify.git
cd inji-verify/docker-compose

# Start services
docker compose up -d
```

### 7.2 Configure Credential Types

Edit `docker-compose/config/config.json` to add your credential type:

```json
{
  "verifiableClaims": [
    {
      "logo": "/assets/cert.png",
      "name": "Employment Credential",
      "type": "EmploymentCredential",
      "clientIdScheme": "did",
      "definition": {
        "purpose": "Verify employment credential",
        "format": {
          "ldp_vc": {
            "proof_type": ["Ed25519Signature2018"]
          }
        },
        "input_descriptors": [
          {
            "id": "employment credential",
            "format": {
              "ldp_vc": {
                "proof_type": ["Ed25519Signature2018"]
              }
            },
            "constraints": {
              "fields": [
                {
                  "path": ["$.type"],
                  "filter": {
                    "type": "object",
                    "pattern": "EmploymentCredential"
                  }
                }
              ]
            }
          }
        ]
      }
    }
  ]
}
```

### 7.3 Restart Inji Verify

```bash
docker compose restart verify-ui
```

### 7.4 Access Inji Verify

Open in browser: `http://YOUR_SERVER_IP:3000`

---

## Part 8: Verification

### 8.1 Scan QR Code with Inji Verify

1. Open Inji Verify web interface
2. Click "Scan QR Code"
3. Allow camera access
4. Point camera at the credential QR code
5. View verification result

### 8.2 Direct API Verification

```bash
# Test verification via API
curl -X POST http://YOUR_SERVER_IP:3000/v1/verify/vc-verification \
  -H "Content-Type: application/json" \
  -d @credential.json

# Expected response:
# {"verificationStatus":"SUCCESS"}
```

---

## Troubleshooting

### Agent Issues

| Problem | Solution |
|---------|----------|
| Agent restart loop | Check PostgreSQL is running: `docker ps \| grep postgres` |
| "jwt malformed" error | Use `/agent/token` endpoint to get JWT, not raw API key |
| Connection refused | Verify correct port (8003 for admin, 9003 for DIDComm) |

### Connection Issues

| Problem | Solution |
|---------|----------|
| Connection stuck in "request" | Check tunnel is active, restart if 503 errors |
| Mobile wallet can't connect | Verify tunnel URL in agent config matches active tunnel |
| Old connection not working | Create new OOB invitation (endpoint is embedded in DID) |

### Credential Issues

| Problem | Solution |
|---------|----------|
| "protected term redefinition" | Use `credentials/examples/v1` context, not `ed25519-2018/v1` |
| Stuck in "request-received" | Check agent logs for JSON-LD errors |
| Signature verification fails | Ensure `Ed25519Signature2018` proof type matches DID key type |

### QR Code Issues

| Problem | Solution |
|---------|----------|
| "No QRCode Found" | Use PixelPass encoding, not raw JSON |
| "Invalid character at position X" | Use PNG QR instead of terminal rendering |
| "Page Not Found" | Don't use `INJI_OVP://` header for direct verification |

### Inji Verify Issues

| Problem | Solution |
|---------|----------|
| Credential type not recognized | Add type to `config.json` and restart `verify-ui` |
| Verification fails | Test with direct API call to isolate QR vs credential issue |

---

## Quick Reference Scripts

### Complete Issuance Pipeline

```bash
#!/bin/bash
# complete-issuance.sh

API_KEY="supersecret-that-too-16chars"
AGENT_URL="http://localhost:8003"

# 1. Get token
JWT=$(curl -s -X POST "$AGENT_URL/agent/token" \
  -H "authorization: $API_KEY" | jq -r '.token')

# 2. Create invitation
INVITATION=$(curl -s -X POST "$AGENT_URL/didcomm/oob/create-invitation" \
  -H "authorization: $JWT" \
  -H "Content-Type: application/json" \
  -d '{"label":"Issuer","handshake":true,"autoAcceptConnection":true}')

echo "Scan this QR code with your wallet:"
echo "$INVITATION" | jq -r '.invitationUrl' | qrencode -t ANSIUTF8

echo "Press Enter after accepting connection..."
read

# 3. Get connection ID
CONNECTION_ID=$(curl -s -H "authorization: $JWT" "$AGENT_URL/didcomm/connections" \
  | jq -r '.[] | select(.state == "completed") | .id' | head -1)

# 4. Issue credential
./scripts/issue-and-generate-qr.sh "$CONNECTION_ID" --api-key "$API_KEY"
```

### Environment Setup Check

```bash
#!/bin/bash
# check-environment.sh

echo "Checking environment..."

# Check Docker
docker ps &>/dev/null && echo "✓ Docker running" || echo "✗ Docker not running"

# Check PostgreSQL
docker ps | grep -q postgres && echo "✓ PostgreSQL running" || echo "✗ PostgreSQL not running"

# Check Agent
curl -s http://localhost:8003/agent &>/dev/null && echo "✓ Agent accessible" || echo "✗ Agent not accessible"

# Check Node.js
node -v &>/dev/null && echo "✓ Node.js installed" || echo "✗ Node.js not installed"

# Check PixelPass
node -e "require('@injistack/pixelpass')" 2>/dev/null && echo "✓ PixelPass installed" || echo "✗ PixelPass not installed"

# Check qrencode
command -v qrencode &>/dev/null && echo "✓ qrencode installed" || echo "✗ qrencode not installed"
```

---

## File Structure

```
credebl-w3c-credential-issuance/
├── README.md
├── docs/
│   ├── credential-issuance-to-verification.md   # Quick guide
│   └── complete-setup-guide.md                  # This document
├── scripts/
│   ├── issue-and-generate-qr.sh                 # Full issuance pipeline
│   ├── encode-credential.js                     # PixelPass encoder
│   ├── generate-qr-from-credential.sh           # QR from existing credential
│   └── start-tunnel.sh                          # SSH tunnel helper
├── postman/
│   ├── CREDEBL-W3C-Issuance.postman_collection.json
│   └── CREDEBL-W3C-Issuance.postman_environment.json
└── examples/
    └── sample-credentials.json
```

---

## Support

- **CREDEBL Platform:** https://github.com/credebl/platform/issues
- **credo-controller:** https://github.com/credebl/credo-controller/issues
- **Inji Verify:** https://github.com/mosip/inji-verify/issues
- **Credo (AFJ):** https://github.com/openwallet-foundation/credo-ts/issues
