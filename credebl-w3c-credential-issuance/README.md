# CREDEBL W3C Credential Issuance Guide

This guide documents the complete process for issuing W3C JSON-LD Verifiable Credentials from a CREDEBL dedicated agent to a mobile wallet (e.g., Sovio).

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Architecture Overview](#architecture-overview)
3. [Setup Process](#setup-process)
4. [Credential Issuance Flow](#credential-issuance-flow)
5. [API Reference](#api-reference)
6. [Troubleshooting](#troubleshooting)
7. [Key Learnings](#key-learnings)

---

## Prerequisites

### Required Components

- **CREDEBL Platform** with a dedicated agent deployed
- **credo-controller** container running (ghcr.io/credebl/credo-controller:latest)
- **PostgreSQL** database for wallet storage
- **SSH Tunnel** or public endpoint for DIDComm messaging
- **Mobile Wallet** supporting DIDComm and W3C credentials (e.g., Sovio)

### Agent Configuration

The agent must be configured with:
- Valid wallet credentials
- Public endpoint accessible by mobile wallets
- Auto-accept settings for connections

Example agent config (`agent-config.json`):
```json
{
  "label": "YOUR_ORG_ID_YOUR_ORG_NAME",
  "walletId": "YourWallet",
  "walletKey": "YourWalletKey",
  "walletType": "postgres",
  "walletUrl": "YOUR_POSTGRES_HOST:PORT",
  "walletAccount": "postgres",
  "walletPassword": "postgres",
  "walletAdminAccount": "postgres",
  "walletAdminPassword": "postgres",
  "walletScheme": "DatabasePerWallet",
  "endpoint": ["https://YOUR_PUBLIC_ENDPOINT"],
  "autoAcceptConnections": true,
  "autoAcceptCredentials": "contentApproved",
  "autoAcceptProofs": "contentApproved",
  "logLevel": 2,
  "inboundTransport": [{"transport": "http", "port": 9004}],
  "outboundTransport": ["http"],
  "adminPort": 8004,
  "tenancy": false,
  "apiKey": "YOUR_API_KEY" /*e.g., "supersecret-that-too-16chars" */
}
```

---

## Architecture Overview

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Mobile Wallet  │────▶│   SSH Tunnel     │────▶│  credo-controller│
│    (Sovio)      │◀────│ (localhost.run)  │◀────│   (Port 9004)   │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                                                         │
                              ┌──────────────────────────┘
                              ▼
                        ┌─────────────────┐
                        │   PostgreSQL    │
                        │  Wallet Storage │
                        └─────────────────┘
```

### Ports

| Port | Purpose |
|------|---------|
| 8004 | Admin API (REST endpoints) |
| 9004 | DIDComm Inbound Transport |

---

## Setup Process

### Step 1: Start SSH Tunnel

The mobile wallet needs a public endpoint to communicate with your agent. Use localhost.run to create an SSH tunnel:

```bash
# Start tunnel (run the provided script)
./scripts/start-tunnel.sh

# The script will output a URL like:
# https://abc123def456.lhr.life
```

### Step 2: Update Agent Configuration

Update your agent config with the new tunnel URL:

```bash
# Edit the endpoint in your agent config
# Change: "endpoint": ["https://OLD_URL"]
# To:     "endpoint": ["https://NEW_TUNNEL_URL"]
```

### Step 3: Restart Agent Container

```bash
docker restart YOUR_AGENT_CONTAINER_NAME
```

### Step 4: Verify Agent is Running

```bash
curl -H "authorization: YOUR_API_KEY" http://localhost:8004/agent
```

Expected response:
```json
{
  "label": "YOUR_AGENT_LABEL",
  "endpoints": ["https://YOUR_TUNNEL_URL"],
  "isInitialized": true
}
```

---

## Credential Issuance Flow

### Flow Diagram

```
┌────────────┐                              ┌────────────┐
│   Issuer   │                              │   Holder   │
│   Agent    │                              │   Wallet   │
└─────┬──────┘                              └─────┬──────┘
      │                                           │
      │  1. Create OOB Invitation                 │
      │──────────────────────────────────────────▶│
      │                                           │
      │  2. Scan QR Code / Accept Invitation      │
      │◀──────────────────────────────────────────│
      │                                           │
      │  3. Connection Established                │
      │◀─────────────────────────────────────────▶│
      │                                           │
      │  4. Send Credential Offer                 │
      │──────────────────────────────────────────▶│
      │                                           │
      │  5. Holder Accepts Offer                  │
      │◀──────────────────────────────────────────│
      │                                           │
      │  6. Holder Sends Request                  │
      │◀──────────────────────────────────────────│
      │                                           │
      │  7. Issue Credential                      │
      │──────────────────────────────────────────▶│
      │                                           │
      │  8. Holder Acknowledges                   │
      │◀──────────────────────────────────────────│
      │                                           │
      │  State: DONE                              │
      │                                           │
```

### Credential Exchange States

| State | Description |
|-------|-------------|
| `offer-sent` | Issuer has sent credential offer |
| `proposal-received` | Issuer received holder's proposal |
| `request-received` | Issuer received holder's request |
| `credential-issued` | Credential has been issued |
| `done` | Exchange completed successfully |

---

## API Reference

### Authentication

All API requests require the `authorization` header:
```
authorization: YOUR_API_KEY
```

### Base URL

```
http://localhost:8004
```

### Endpoints

#### 1. Get Agent Info
```http
GET /agent
```

#### 2. Create Out-of-Band Invitation
```http
POST /didcomm/oob/create-invitation
Content-Type: application/json

{
  "label": "CREDEBL Issuer",
  "goalCode": "issue-vc",
  "goal": "Issue Verifiable Credential",
  "handshake": true,
  "handshakeProtocols": [
    "https://didcomm.org/didexchange/1.x",
    "https://didcomm.org/connections/1.x"
  ],
  "autoAcceptConnection": true
}
```

#### 3. List Connections
```http
GET /didcomm/connections
```

#### 4. Get Connection by ID
```http
GET /didcomm/connections/{connectionId}
```

#### 5. Create Credential Offer
```http
POST /didcomm/credentials/create-offer
Content-Type: application/json

{
  "connectionId": "CONNECTION_ID",
  "protocolVersion": "v2",
  "credentialFormats": {
    "jsonld": {
      "credential": {
        "@context": [
          "https://www.w3.org/2018/credentials/v1",
          "https://www.w3.org/2018/credentials/examples/v1"
        ],
        "type": ["VerifiableCredential", "EmploymentCredential"],
        "issuer": "did:key:YOUR_DID_KEY",
        "issuanceDate": "2026-01-15T00:00:00Z",
        "credentialSubject": {
          "id": "did:key:HOLDER_DID_KEY",
          "employeeOf": {
            "name": "Organization Name",
            "position": "Job Title",
            "startDate": "2024-01-01"
          }
        }
      },
      "options": {
        "proofType": "Ed25519Signature2018",
        "proofPurpose": "assertionMethod"
      }
    }
  },
  "autoAcceptCredential": "always"
}
```

#### 6. List Credential Exchange Records
```http
GET /didcomm/credentials/
```

#### 7. Get Credential by ID
```http
GET /didcomm/credentials/{credentialRecordId}
```

#### 8. Get Credential Format Data
```http
GET /didcomm/credentials/{credentialRecordId}/form-data
```

#### 9. Get DIDs
```http
GET /dids
```

---

## Troubleshooting

### Common Issues

#### 1. "Cannot GET /endpoint" Errors

**Cause:** Using wrong API path prefix.

**Solution:** All credential and connection endpoints are under `/didcomm/`:
- ❌ `/credentials`
- ✅ `/didcomm/credentials/`

#### 2. "Unauthorized" Response

**Cause:** Missing or incorrect API key.

**Solution:** Use plain `authorization` header (not Bearer):
```
authorization: YOUR_API_KEY
```

#### 3. JSON-LD Protected Term Redefinition Error

**Error:**
```
Invalid JSON-LD syntax; tried to redefine "Ed25519Signature2018" which is a protected term.
```

**Cause:** Using `https://w3id.org/security/suites/ed25519-2018/v1` context.

**Solution:** Use `https://www.w3.org/2018/credentials/examples/v1` instead:
```json
{
  "@context": [
    "https://www.w3.org/2018/credentials/v1",
    "https://www.w3.org/2018/credentials/examples/v1"
  ]
}
```

#### 4. "Missing verification method for key type Ed25519VerificationKey2020"

**Cause:** Trying to use `Ed25519Signature2020` proof type with a DID that has `Ed25519VerificationKey2018`.

**Solution:** Use `Ed25519Signature2018` proof type or create a new DID with Ed25519VerificationKey2020.

#### 5. Credential Stuck at "request-received"

**Cause:** JSON-LD context issues preventing signature creation.

**Solution:** Check agent logs for specific error:
```bash
docker logs YOUR_CONTAINER_NAME 2>&1 | grep -i error | tail -20
```

#### 6. SSH Tunnel 503 Errors

**Cause:** localhost.run tunnel expired or disconnected.

**Solution:** Restart the tunnel and update agent config:
```bash
./scripts/start-tunnel.sh
# Then update agent config and restart container
```

#### 7. Connection Not Established

**Cause:** Handshake protocol version mismatch.

**Solution:** Use `.x` suffix for protocol versions:
```json
{
  "handshakeProtocols": [
    "https://didcomm.org/didexchange/1.x",
    "https://didcomm.org/connections/1.x"
  ]
}
```

---

## Key Learnings

### 1. JSON-LD Context Selection is Critical

The choice of JSON-LD context directly affects whether credentials can be signed:

| Context | Compatible with Ed25519Signature2018? |
|---------|--------------------------------------|
| `https://www.w3.org/2018/credentials/examples/v1` | ✅ Yes |
| `https://w3id.org/security/suites/ed25519-2018/v1` | ❌ No (protected term conflict) |
| `https://w3id.org/security/suites/ed25519-2020/v1` | ❌ No (requires Ed25519VerificationKey2020) |

### 2. API Authentication Format

The credo-controller uses a plain `authorization` header, not Bearer token:
```
# Correct
authorization: YOUR_API_KEY

# Incorrect
Authorization: Bearer YOUR_API_KEY
```

### 3. Endpoint Prefix

All DIDComm-related endpoints use the `/didcomm/` prefix:
- `/didcomm/credentials/`
- `/didcomm/connections`
- `/didcomm/oob/`
- `/didcomm/proofs/`

### 4. Auto-Accept Settings

For seamless credential issuance, use:
```json
{
  "autoAcceptCredential": "always"
}
```

This allows the agent to automatically progress through the credential exchange states.

### 5. Tunnel Reliability

localhost.run tunnels can expire. For production:
- Use a stable reverse proxy (ngrok pro, Cloudflare Tunnel)
- Or deploy with a public IP/domain

---

## Files in This Package

```
credebl-w3c-credential-issuance/
├── README.md                    # This documentation
├── postman/
│   └── CREDEBL-W3C-Issuance.postman_collection.json
├── scripts/
│   ├── start-tunnel.sh          # SSH tunnel script
│   ├── generate-qr.py           # QR code generator
│   └── monitor-credential.sh    # Credential state monitor
└── examples/
    └── sample-credentials.json  # Sample credential payloads
```

---

## Support

For issues with:
- **CREDEBL Platform:** https://github.com/credebl/platform/issues
- **credo-controller:** https://github.com/credebl/credo-controller/issues
- **Credo (AFJ):** https://github.com/openwallet-foundation/credo-ts/issues
