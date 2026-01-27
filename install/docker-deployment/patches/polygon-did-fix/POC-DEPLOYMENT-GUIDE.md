# CREDEBL + Inji Verify Integration: Proof of Concept Deployment Guide

## Overview

This guide documents the integration of **CREDEBL** (for W3C Verifiable Credential issuance on blockchain) with **Inji Verify** (for credential verification). The PoC demonstrates:

1. Issuing W3C Verifiable Credentials using `did:polygon` on Polygon Mainnet
2. Verifying those credentials through Inji Verify's QR scanning interface

## Architecture

### High-Level Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           CREDENTIAL ISSUANCE                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────────────┐  │
│  │   CREDEBL    │───▶│   Credo-TS   │───▶│   Polygon Mainnet        │  │
│  │   Platform   │    │   Agent      │    │   (DID Registry)         │  │
│  └──────────────┘    └──────────────┘    └──────────────────────────┘  │
│         │                   │                                           │
│         │                   ▼                                           │
│         │            ┌──────────────┐                                   │
│         │            │  Credential  │                                   │
│         │            │  with Proof  │                                   │
│         │            └──────────────┘                                   │
│         │                   │                                           │
│         ▼                   ▼                                           │
│  ┌──────────────────────────────────────┐                              │
│  │  JSON-XT Compression (optional)      │                              │
│  │  JSON-LD (~1400B) → JSON-XT (~500B)  │                              │
│  └──────────────────────────────────────┘                              │
│         │                                                               │
│         ▼                                                               │
│  ┌──────────────────────────────────────┐                              │
│  │  PixelPass QR Encoding               │                              │
│  │  (zlib + base45 + QR)                │                              │
│  └──────────────────────────────────────┘                              │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│                         CREDENTIAL VERIFICATION                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────────────┐  │
│  │  Inji Verify │───▶│   Adapter    │───▶│   CREDEBL Agent          │  │
│  │  UI (:3001)  │    │   Service    │    │   Verification API       │  │
│  └──────────────┘    └──────────────┘    └──────────────────────────┘  │
│         │                                          │                    │
│         │                                          ▼                    │
│         │                                 ┌──────────────────────────┐  │
│         │                                 │   Polygon Mainnet        │  │
│         │                                 │   (Resolve DID Doc)      │  │
│         │                                 └──────────────────────────┘  │
│         │                                          │                    │
│         ▼                                          ▼                    │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                    Verification Result: SUCCESS/INVALID           │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Detailed Adapter Architecture

The verification adapter handles multiple input formats and routes to appropriate backends:

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              INJI VERIFY UI                                      │
│                            (Browser/Mobile)                                      │
└─────────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      │ QR Scan / Upload
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                               NGINX PROXY                                        │
│                              (Port 3001/8000)                                    │
│  ┌────────────────────────────────────────────────────────────────────────────┐ │
│  │  /v1/verify/vc-verification  ──────────────▶  verification-adapter:8085   │ │
│  │  /v1/verify/*                ──────────────▶  inji-verify-service:8080    │ │
│  └────────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        VERIFICATION ADAPTER (Port 8085)                          │
│                                                                                  │
│  ┌────────────────────────────────────────────────────────────────────────────┐ │
│  │                         REQUEST PARSING LAYER                              │ │
│  │                                                                            │ │
│  │   Input Data ─────┬─────────────────────────────────────────────────────▶ │ │
│  │                   │                                                        │ │
│  │                   ▼                                                        │ │
│  │   ┌─────────────────────────┐    ┌─────────────────────────┐             │ │
│  │   │   PixelPass Detector    │    │   Format: NCFF-...      │             │ │
│  │   │   isPixelPassEncoded()  │───▶│   Base45 encoded        │             │ │
│  │   └─────────────────────────┘    └───────────┬─────────────┘             │ │
│  │                                              │                            │ │
│  │                                              ▼                            │ │
│  │                                  ┌─────────────────────────┐             │ │
│  │                                  │   @mosip/pixelpass      │             │ │
│  │                                  │   decode()              │             │ │
│  │                                  └───────────┬─────────────┘             │ │
│  │                                              │                            │ │
│  │                   ┌──────────────────────────┴──────────────────────────┐│ │
│  │                   │                                                      ││ │
│  │                   ▼                                                      ▼│ │
│  │   ┌─────────────────────────┐                    ┌─────────────────────┐│ │
│  │   │   JSON-XT Detector      │                    │   JSON Detector     ││ │
│  │   │   isJsonXtUri()         │                    │   startsWith('{')   ││ │
│  │   │   Format: jxt:...       │                    │                     ││ │
│  │   └───────────┬─────────────┘                    └──────────┬──────────┘│ │
│  │               │                                             │           │ │
│  │               ▼                                             │           │ │
│  │   ┌─────────────────────────┐                              │           │ │
│  │   │   jsonxt library        │                              │           │ │
│  │   │   + local templates     │                              │           │ │
│  │   │   decode()              │                              │           │ │
│  │   └───────────┬─────────────┘                              │           │ │
│  │               │                                             │           │ │
│  │               ▼                                             ▼           │ │
│  │   ┌─────────────────────────────────────────────────────────────────┐  │ │
│  │   │                    JSON-LD CREDENTIAL                           │  │ │
│  │   │   { "@context": [...], "type": [...], "credentialSubject": {} } │  │ │
│  │   └─────────────────────────────────────────────────────────────────┘  │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                      │                                       │
│                                      ▼                                       │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                         ROUTING LAYER                                   │ │
│  │                                                                         │ │
│  │   Extract Issuer DID ──▶ Determine DID Method ──▶ Route to Backend     │ │
│  │                                                                         │ │
│  │   ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐  │ │
│  │   │ did:polygon:... │────▶│ CREDEBL Agent   │────▶│ Polygon Mainnet │  │ │
│  │   └─────────────────┘     │ (Port 8004)     │     │ (DID Resolution)│  │ │
│  │                           └─────────────────┘     └─────────────────┘  │ │
│  │                                                                         │ │
│  │   ┌─────────────────┐     ┌─────────────────┐                          │ │
│  │   │ did:web:...     │────▶│ Inji Verify     │                          │ │
│  │   │ did:key:...     │     │ Service         │                          │ │
│  │   │ did:jwk:...     │     │ (Port 8080)     │                          │ │
│  │   └─────────────────┘     └─────────────────┘                          │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                      │                                       │
│                                      ▼                                       │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                         RESPONSE LAYER                                  │ │
│  │                                                                         │ │
│  │   {                                                                     │ │
│  │     "verificationStatus": "SUCCESS" | "INVALID" | "ERROR",             │ │
│  │     "online": true | false,                                            │ │
│  │     "backend": "credebl-agent" | "inji-verify",                        │ │
│  │     "vc": { ... decoded credential for UI display ... },               │ │
│  │     "verifiableCredential": { ... same as vc ... },                    │ │
│  │     "details": { ... verification details ... }                        │ │
│  │   }                                                                     │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Data Flow for Format Detection

```
  Raw Input (from QR scan or API call)
      │
      ▼
  ┌───────────────────┐
  │ Is PixelPass?     │──── Yes ───▶ pixelpass.decode() ───┐
  │ /^[A-Z0-9 $%*+./  │              (base45 + zlib)       │
  │ :_-]+$/i          │                                    │
  └─────────┬─────────┘                                    │
            │ No                                           │
            ▼                                              ▼
  ┌───────────────────┐                          ┌─────────────────┐
  │ Is JSON-XT?       │──── Yes ───▶ jsonxt     │ Decoded String  │
  │ startsWith('jxt:')│              .decode()   │ (may be jxt:    │
  └─────────┬─────────┘                 │        │  or JSON)       │
            │ No                        │        └────────┬────────┘
            ▼                           │                 │
  ┌───────────────────┐                │                 ▼
  │ Is JSON?          │                │        ┌─────────────────┐
  │ startsWith('{')   │                │        │ Is JSON-XT?     │─ Yes ─▶ jsonxt.decode()
  └─────────┬─────────┘                │        │ startsWith      │              │
            │ Yes                      │        │ ('jxt:')        │              │
            ▼                          │        └────────┬────────┘              │
  ┌───────────────────┐                │                 │ No                    │
  │ JSON.parse()      │                │                 ▼                       │
  └─────────┬─────────┘                │        ┌─────────────────┐              │
            │                          │        │ JSON.parse()    │              │
            ▼                          ▼        └────────┬────────┘              │
  ┌────────────────────────────────────────────────────────────────────────────────┐
  │                              JSON-LD CREDENTIAL                                 │
  │                                                                                 │
  │  {                                                                              │
  │    "@context": ["https://www.w3.org/2018/credentials/v1", ...],                │
  │    "type": ["VerifiableCredential", "EducationCredential"],                    │
  │    "issuer": "did:polygon:0x...",                                              │
  │    "credentialSubject": { "name": "...", "degree": "...", ... },               │
  │    "proof": { "type": "EcdsaSecp256k1Signature2019", "jws": "..." }            │
  │  }                                                                              │
  └────────────────────────────────────────────────────────────────────────────────┘
```

### Adapter Dependencies

| Package | Purpose |
|---------|---------|
| `@mosip/pixelpass` | Decode PixelPass QR data (base45 + zlib) |
| `jsonxt` | Decode JSON-XT compressed credentials |
| `better-sqlite3` | SQLite for offline issuer cache |

### Supported Input Formats

| Format | Example | Detection | Processing |
|--------|---------|-----------|------------|
| PixelPass | `NCFF-J91S7MJ...` | Base45 character set | Decode → re-detect |
| JSON-XT URI | `jxt:local:educ:1:...` | Starts with `jxt:` | Decode with templates |
| JSON-LD | `{"@context":...}` | Starts with `{` | Parse directly |
| Wrapped | `{"credential":{...}}` | Has credential field | Unwrap and process |

## Components

| Component | Purpose | Port |
|-----------|---------|------|
| CREDEBL Platform | Credential management UI/API | 8030 |
| CREDEBL Agent (Credo-TS) | DID operations, credential signing | 8004 |
| Inji Verify UI | QR scanning and verification display | 3000 |
| Inji Verify Service | Original verification backend | 8082 |
| CREDEBL-Inji Adapter | Bridges Inji API to CREDEBL verification | 8085 |
| Nginx Proxy | Routes verification requests to adapter | 8080 |

---

## Part 1: CREDEBL Setup for did:polygon

### 1.1 Prerequisites

- CREDEBL platform deployed (Docker or local)
- Polygon Mainnet RPC endpoint (e.g., Infura, Alchemy, or public RPC)
- Ethereum wallet with MATIC for transaction fees

### 1.2 Agent Configuration

The CREDEBL agent requires polygon DID method configuration. Update your agent configuration file:

```json
{
  "label": "YourOrgName",
  "walletId": "your-wallet-id",
  "walletKey": "your-wallet-key",
  "walletType": "postgres",
  "indyLedger": [],
  "publicDidSeed": "your-32-character-seed-here-xxxx",
  "endpoint": ["https://your-agent-endpoint.com"],
  "autoAcceptConnections": true,
  "autoAcceptCredentials": "always",
  "autoAcceptProofs": "always",
  "logLevel": 2,
  "inboundTransport": [{"transport": "http", "port": 4002}],
  "outboundTransport": ["http", "https"],
  "polygonDid": {
    "rpcUrl": "https://polygon-mainnet.infura.io/v3/YOUR_INFURA_KEY",
    "didContractAddress": "0x0C16958c4246271622201101C83B9F0Fc7180d15",
    "fileServerUrl": "",
    "schemaManagerContractAddress": "0x988C4B393f1e05E3DC7e0b8f66eae59582bD8BD3",
    "serverUrl": ""
  }
}
```

### 1.3 Creating a did:polygon DID

Use the CREDEBL agent API to create a polygon DID:

```bash
# Get authentication token
TOKEN=$(curl -s -X POST http://localhost:8004/agent/token \
  -H "Authorization: YOUR_API_KEY" | jq -r '.token')

# Create polygon DID
curl -X POST http://localhost:8004/dids/create \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "method": "polygon",
    "options": {
      "network": "mainnet",
      "endpoint": "https://polygon-mainnet.infura.io/v3/YOUR_KEY"
    },
    "secret": {
      "privateKey": "YOUR_ETHEREUM_PRIVATE_KEY_HEX"
    }
  }'
```

### 1.4 Registering DID Document On-Chain

The DID document must be registered on Polygon with the correct public key format:

```bash
# Using cast (foundry) to call the registry contract
cast send 0x0C16958c4246271622201101C83B9F0Fc7180d15 \
  "createDID(address,string)" \
  YOUR_ETH_ADDRESS \
  '{"@context":"https://w3id.org/did/v1","id":"did:polygon:YOUR_ADDRESS","verificationMethod":[{"id":"did:polygon:YOUR_ADDRESS#key-1","type":"EcdsaSecp256k1VerificationKey2019","controller":"did:polygon:YOUR_ADDRESS","publicKeyBase58":"YOUR_PUBLIC_KEY_BASE58"}],"authentication":["did:polygon:YOUR_ADDRESS#key-1"],"assertionMethod":["did:polygon:YOUR_ADDRESS#key-1"]}' \
  --rpc-url https://polygon-mainnet.infura.io/v3/YOUR_KEY \
  --private-key YOUR_PRIVATE_KEY
```

**Important**: The `publicKeyBase58` must be the compressed secp256k1 public key encoded in Base58.

### 1.5 Issuing a Credential

```bash
# Issue W3C credential via CREDEBL agent
curl -X POST http://localhost:8004/agent/credential/issue \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "credential": {
      "@context": [
        "https://www.w3.org/2018/credentials/v1",
        {
          "EmploymentCredential": "https://schema.org/EmployeeRole",
          "employeeName": "https://schema.org/name",
          "employerName": "https://schema.org/legalName",
          "jobTitle": "https://schema.org/jobTitle"
        }
      ],
      "type": ["VerifiableCredential", "EmploymentCredential"],
      "issuer": "did:polygon:YOUR_DID_ADDRESS",
      "issuanceDate": "2026-01-20T00:00:00Z",
      "credentialSubject": {
        "type": "EmploymentCredential",
        "employeeName": "John Doe",
        "employerName": "Acme Corp",
        "jobTitle": "Engineer",
        "id": "did:example:holder123"
      }
    },
    "options": {
      "proofType": "EcdsaSecp256k1Signature2019",
      "proofPurpose": "assertionMethod"
    }
  }'
```

---

## Part 2: CREDEBL-Inji Adapter Service

The adapter bridges Inji Verify's API format to CREDEBL's verification API.

### 2.1 Adapter Source Code

Create `adapter.js`:

```javascript
#!/usr/bin/env node
/**
 * CREDEBL-to-Inji Verify Adapter
 *
 * Bridges Inji Verify verification requests to CREDEBL agent.
 */

const http = require('http');

// Configuration
const ADAPTER_PORT = process.env.ADAPTER_PORT || 8085;
const CREDEBL_AGENT_URL = process.env.CREDEBL_AGENT_URL || 'http://localhost:8004';
const CREDEBL_API_KEY = process.env.CREDEBL_API_KEY || 'your-api-key';

// Helper to make HTTP requests
function httpRequest(options, postData) {
    return new Promise((resolve, reject) => {
        const req = http.request(options, (res) => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => {
                try {
                    resolve({ status: res.statusCode, data: JSON.parse(data) });
                } catch (e) {
                    resolve({ status: res.statusCode, data: data });
                }
            });
        });
        req.on('error', reject);
        if (postData) req.write(postData);
        req.end();
    });
}

// Get JWT token from CREDEBL agent
async function getJwtToken() {
    const url = new URL(CREDEBL_AGENT_URL);
    const options = {
        hostname: url.hostname,
        port: url.port || 80,
        path: '/agent/token',
        method: 'POST',
        headers: { 'Authorization': CREDEBL_API_KEY }
    };

    const response = await httpRequest(options);
    if (response.data && response.data.token) {
        return response.data.token;
    }
    throw new Error('Failed to get JWT token: ' + JSON.stringify(response.data));
}

// Verify credential via CREDEBL agent
async function verifyCredential(credential) {
    const token = await getJwtToken();
    const url = new URL(CREDEBL_AGENT_URL);

    const postData = JSON.stringify({ credential: credential });
    const options = {
        hostname: url.hostname,
        port: url.port || 80,
        path: '/agent/credential/verify',
        method: 'POST',
        headers: {
            'Authorization': 'Bearer ' + token,
            'Content-Type': 'application/json',
            'Content-Length': Buffer.byteLength(postData)
        }
    };

    const response = await httpRequest(options, postData);
    return response.data;
}

// Map CREDEBL response to Inji Verify format
function mapToInjiFormat(credeblResponse) {
    if (credeblResponse && credeblResponse.isValid === true) {
        return { verificationStatus: 'SUCCESS' };
    }
    return { verificationStatus: 'INVALID' };
}

// HTTP Server
const server = http.createServer(async (req, res) => {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

    if (req.method === 'OPTIONS') {
        res.writeHead(200);
        res.end();
        return;
    }

    if (req.method === 'GET' && (req.url === '/health' || req.url === '/')) {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ status: 'ok', service: 'credebl-inji-adapter' }));
        return;
    }

    if (req.method === 'POST' && req.url === '/v1/verify/vc-verification') {
        let body = '';
        req.on('data', chunk => body += chunk);
        req.on('end', async () => {
            try {
                const request = JSON.parse(body);
                console.log('[ADAPTER] Received v1 verification request');

                // Support multiple input formats
                let credential;
                if (request.verifiableCredentials && request.verifiableCredentials.length > 0) {
                    credential = request.verifiableCredentials[0];
                } else if (request.credential) {
                    credential = request.credential;
                } else if (request['@context']) {
                    credential = request;
                } else {
                    res.writeHead(400, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ verificationStatus: 'INVALID', error: 'No credentials found' }));
                    return;
                }

                console.log('[ADAPTER] Verifying credential with issuer:', credential.issuer);

                const credeblResult = await verifyCredential(credential);
                console.log('[ADAPTER] CREDEBL result: isValid =', credeblResult.isValid);

                const injiResult = mapToInjiFormat(credeblResult);
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify(injiResult));
            } catch (error) {
                console.error('[ADAPTER] Error:', error.message);
                res.writeHead(500, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ verificationStatus: 'INVALID', error: error.message }));
            }
        });
        return;
    }

    res.writeHead(404, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Not found' }));
});

server.listen(ADAPTER_PORT, '0.0.0.0', () => {
    console.log('CREDEBL-to-Inji Verify Adapter');
    console.log('Listening on port:', ADAPTER_PORT);
    console.log('CREDEBL Agent URL:', CREDEBL_AGENT_URL);
});
```

### 2.2 Running the Adapter

```bash
# Install dependencies (none required - uses Node.js built-ins)

# Run the adapter
ADAPTER_PORT=8085 \
CREDEBL_AGENT_URL=http://localhost:8004 \
CREDEBL_API_KEY=your-api-key \
node adapter.js
```

### 2.3 Docker Deployment (Optional)

Create `Dockerfile`:

```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY adapter.js .
EXPOSE 8085
CMD ["node", "adapter.js"]
```

```bash
docker build -t credebl-inji-adapter .
docker run -d \
  -p 8085:8085 \
  -e CREDEBL_AGENT_URL=http://host.docker.internal:8004 \
  -e CREDEBL_API_KEY=your-api-key \
  credebl-inji-adapter
```

---

## Part 3: Inji Verify Modifications

### 3.1 Overview of Changes

Inji Verify requires two modifications:
1. **verify-service port change**: Move from 8080 to 8082 to allow nginx proxy
2. **verify-ui nginx config**: Route verification requests through the adapter

### 3.2 Modify Docker Compose

Edit `docker-compose.yml` for Inji Verify:

```yaml
services:
  verify-service:
    image: mosipdev/inji-verify-service:develop
    ports:
      - "8082:8080"  # Changed from 8080:8080
    # ... rest of config

  verify-ui:
    image: mosipdev/inji-verify-ui:develop
    ports:
      - "3000:8000"
    # ... rest of config
```

### 3.3 Host Nginx Configuration

Create `/etc/nginx/sites-available/inji-adapter`:

```nginx
server {
    listen 8080;
    server_name _;

    # Verification endpoint - proxy to CREDEBL adapter
    location /v1/verify/vc-verification {
        proxy_pass http://localhost:8085;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Content-Type $http_content_type;
    }

    # All other requests - proxy to original verify-service
    location / {
        proxy_pass http://localhost:8082;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

Enable the configuration:

```bash
sudo ln -s /etc/nginx/sites-available/inji-adapter /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

### 3.4 Modify verify-ui Container's Nginx

The verify-ui container has its own nginx that must route to the host's nginx proxy.

Create the modified config:

```nginx
server {
    listen 8000;
    root   /usr/share/nginx/html;
    index  index.html index.htm;

    error_page 500 502 503 504 /50x.html;
    location = /50x.html {
        root /usr/share/nginx/html;
    }

    # Proxy to host nginx (which routes to adapter)
    # 172.18.0.1 is the Docker bridge gateway - adjust for your network
    location /v1/verify {
        proxy_pass http://172.18.0.1:8080/v1/verify;
        proxy_redirect     off;
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Host $server_name;
        proxy_set_header   Connection close;
    }

    location /.well-known/did.json {
        proxy_pass http://172.18.0.1:8080/v1/verify/.well-known/did.json;
        proxy_redirect     off;
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Host $server_name;
        proxy_set_header   Connection close;
    }

    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

Apply to the running container:

```bash
# Find Docker bridge gateway IP
GATEWAY_IP=$(docker network inspect docker-compose_default --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}')

# Create config file
cat > /tmp/verify-ui-nginx.conf << EOF
server {
    listen 8000;
    root   /usr/share/nginx/html;
    index  index.html index.htm;

    location /v1/verify {
        proxy_pass http://${GATEWAY_IP}:8080/v1/verify;
        proxy_redirect     off;
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   Connection close;
    }

    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
EOF

# Copy to container and reload
docker cp /tmp/verify-ui-nginx.conf verify-ui:/etc/nginx/conf.d/default.conf
docker exec verify-ui nginx -s reload
```

---

## Part 4: QR Code Generation

### 4.1 Install PixelPass

Inji Verify uses PixelPass encoding for QR codes (zlib compression + base45 encoding):

```bash
npm install @injistack/pixelpass
```

### 4.2 Generate QR Code

```bash
# Generate encoded QR data
node -e "
const { generateQRData } = require('@injistack/pixelpass');
const fs = require('fs');
const credential = JSON.parse(fs.readFileSync('credential.json', 'utf8'));
process.stdout.write(generateQRData(JSON.stringify(credential)));
" > qrdata.txt

# Generate QR image (requires qrencode)
qrencode -o credential-qr.png -s 10 -m 2 < qrdata.txt
```

### 4.3 Alternative: Using the Issuance Script

The `full-issuance-flow.sh` script automates the entire process including QR generation:

```bash
export CREDEBL_API_KEY="your-api-key"
./full-issuance-flow.sh -n "Your Organization" -p "Job Title"
```

### 4.4 JSON-XT Compact Format

The credential issuance scripts support **JSON-XT** (JSON eXternal Templates) output - a standardized compression format from [Consensas](https://github.com/Consensas/jsonxt) that reduces credential size to 25-35% of the original through template-based encoding.

#### What is JSON-XT?

JSON-XT is an open standard for compressing JSON documents into compact URIs:
- Produces URIs like `jxt:resolver:type:version:encoded_data`
- Uses **external templates** to define compression schema
- Achieves 65-75% size reduction through typed encoding
- Templates can be resolved via `.well-known/` URLs or embedded locally

#### Comparison: JSON-LD vs JSON-XT vs CBOR

| Format | Description | Size | Use Case |
|--------|-------------|------|----------|
| **JSON-LD** | Standard W3C VC format with semantic context | Baseline | Interoperability, verification |
| **JSON-XT** | Template-based URI encoding (Consensas standard) | 25-35% of original | QR codes, compact transmission |
| **CBOR** | Binary encoding (used inside PixelPass QR) | ~40% of original | QR codes, IoT |

#### JSON-XT URI Format

A JSON-XT URI follows this structure:

```
jxt:<resolver>:<type>:<version>:<encoded_payload>
```

**Components:**
- `jxt:` - Protocol identifier
- `resolver` - Template source (e.g., `local`, `example.com`)
- `type` - Template type (e.g., `educ`, `empl`)
- `version` - Template version (e.g., `1`)
- `encoded_payload` - Compressed data using template-defined encoders

**Example:**
```
jxt:local:educ:1:did%3Apolygon%3A0xD3A288.../1KQRS4M/did%3Aexample%3Astudent.../Janet~Quinn/...
```

#### Credential Templates

Templates define how credentials are compressed. Each template specifies:
- **columns**: Fields to extract with their encoders
- **template**: Base JSON-LD structure for reconstruction

##### Education Credential Template (`educ:1`)

Located at `templates/jsonxt-templates.json`:

```json
{
  "educ:1": {
    "columns": [
      {"path": "issuer", "encoder": "string"},
      {"path": "issuanceDate", "encoder": "isodatetime-epoch-base32"},
      {"path": "credentialSubject.id", "encoder": "string"},
      {"path": "credentialSubject.name", "encoder": "string"},
      {"path": "credentialSubject.alumniOf", "encoder": "string"},
      {"path": "credentialSubject.degree", "encoder": "string"},
      {"path": "credentialSubject.fieldOfStudy", "encoder": "string"},
      {"path": "credentialSubject.enrollmentDate", "encoder": "isodate-1900-base32"},
      {"path": "credentialSubject.graduationDate", "encoder": "isodate-1900-base32"},
      {"path": "credentialSubject.studentId", "encoder": "string"},
      {"path": "proof.type", "encoder": "string"},
      {"path": "proof.created", "encoder": "isodatetime-epoch-base32"},
      {"path": "proof.verificationMethod", "encoder": "string"},
      {"path": "proof.jws", "encoder": "string"}
    ],
    "template": {
      "@context": ["https://www.w3.org/2018/credentials/v1", {...}],
      "type": ["VerifiableCredential", "EducationCredential"],
      "credentialSubject": {"type": "EducationCredential"},
      "proof": {"proofPurpose": "assertionMethod"}
    }
  }
}
```

##### Employment Credential Template (`empl:1`)

```json
{
  "empl:1": {
    "columns": [
      {"path": "issuer", "encoder": "string"},
      {"path": "issuanceDate", "encoder": "isodatetime-epoch-base32"},
      {"path": "credentialSubject.employeeName", "encoder": "string"},
      {"path": "credentialSubject.employerName", "encoder": "string"},
      {"path": "credentialSubject.jobTitle", "encoder": "string"},
      {"path": "credentialSubject.dateOfJoining", "encoder": "isodate-1900-base32"},
      {"path": "proof.jws", "encoder": "string"}
    ],
    "template": {...}
  }
}
```

#### Supported Encoders

| Encoder | Description | Example |
|---------|-------------|---------|
| `string` | URL-encoded string | `Janet~Quinn` |
| `isodatetime-epoch-base32` | ISO datetime to base32 epoch | `2024-01-27T18:32:06Z` → `1KQRS4M` |
| `isodate-1900-base32` | ISO date to base32 (since 1900) | `2023-09-01` → `A2B` |
| `integer-base32` | Integer to base32 | `42` → `1A` |

#### Generating JSON-XT Output

Use the `-q` flag to generate both JSON-LD and JSON-XT:

**Education Credential:**
```bash
./issue-education-credential.sh \
  --student-name "Diana Muthoni" \
  --institution "University of Nairobi" \
  --degree "Bachelor of Science" \
  --field-of-study "Computer Science" \
  --enrollment-date "2020-09-01" \
  --graduation-date "2024-06-30" \
  -q  # Generates QR + JSON-XT
```

**Employment Credential:**
```bash
./issue-employment-credential.sh \
  --employee-name "John Smith" \
  --employer-name "Acme Corporation" \
  --job-title "Software Engineer" \
  --department "Engineering" \
  --date-of-joining "2023-01-15" \
  --employee-id "EMP001" \
  -q  # Generates QR + JSON-XT
```

**Output files:**
```
/tmp/<type>-credential-*.json       # Original JSON-LD
/tmp/<type>-credential-*-jsonxt.txt # JSON-XT URI (jxt:local:...)
/tmp/<type>-credential-*-qr.png     # QR code image
/tmp/<type>-credential-*-qr.txt     # QR data (PixelPass wrapped)
```

#### Example Size Comparison

| Credential | JSON-LD | JSON-XT URI | Reduction |
|------------|---------|-------------|-----------|
| Education Credential | ~1,400 bytes | ~400 chars | 70-75% |
| Employment Credential | ~1,250 bytes | ~350 chars | 70-75% |

Note: JWS signatures (~180 bytes) are the largest component and limit maximum compression.

#### Encoding and Decoding

**Encoding (credential → JSON-XT URI):**
```bash
node jsonxt-encode.js /tmp/education-credential.json educ 1 local
# Output: jxt:local:educ:1:did%3Apolygon%3A0x.../1KQRS4M/...
```

**Decoding (JSON-XT URI → credential):**
```bash
node jsonxt-decode.js "jxt:local:educ:1:..."
# Output: Full JSON-LD credential
```

#### QR Code Integration

The implementation wraps JSON-XT URIs in PixelPass for Inji Verify compatibility:

1. Credential → JSON-XT URI (compact)
2. JSON-XT URI → PixelPass encoding (base45)
3. PixelPass data → QR code

This ensures compatibility with existing Inji Verify while gaining JSON-XT compression benefits.

#### Implementation Reference

**File locations:**
```
patches/polygon-did-fix/
├── templates/
│   └── jsonxt-templates.json      # Template definitions
├── jsonxt-encode.js               # Encode credential to URI
├── jsonxt-decode.js               # Decode URI to credential
├── issue-education-credential.sh  # Uses educ:1 template
├── issue-employment-credential.sh # Uses empl:1 template
└── POC-DEPLOYMENT-GUIDE.md        # This documentation
```

**NPM Dependencies:**
```bash
npm install jsonxt @injistack/pixelpass
```

#### Creating Custom Templates

To create a JSON-XT template for a new credential type:

1. Define the `columns` array with field paths and appropriate encoders
2. Create the `template` object with static JSON-LD structure
3. Add to `templates/jsonxt-templates.json` with a unique `type:version` key
4. Use appropriate encoders for dates (`isodate-1900-base32`) and datetimes (`isodatetime-epoch-base32`)

**References:**
- [Consensas JSON-XT Repository](https://github.com/Consensas/jsonxt)
- [JSON-XT NPM Package](https://www.npmjs.com/package/jsonxt)

### 4.5 JSON-XT Verification Support

The adapter service now supports verifying credentials in both JSON-LD and JSON-XT formats. This enables QR codes containing compact JSON-XT URIs to be scanned and verified by Inji Verify.

#### How It Works

When the adapter receives a verification request, it automatically detects the credential format:

1. **JSON-XT URI Detection**: Checks if input starts with `jxt:`
2. **Automatic Decoding**: If JSON-XT, decodes to full JSON-LD using local templates
3. **Standard Verification**: Proceeds with normal signature verification

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   QR Scan       │────▶│   Adapter       │────▶│   CREDEBL       │
│   (JSON-XT URI) │     │   (Decode)      │     │   (Verify)      │
└─────────────────┘     └─────────────────┘     └─────────────────┘
        │                       │                       │
   jxt:local:educ:1:...   JSON-LD credential   isValid: true/false
```

#### Supported Input Formats

The adapter accepts these formats at `/v1/verify/vc-verification`:

| Input Format | Example | Handling |
|--------------|---------|----------|
| Raw JSON-XT URI | `jxt:local:educ:1:...` | Decoded automatically |
| JSON-LD credential | `{"@context": [...], ...}` | Passed through |
| Wrapped credential | `{"credential": {...}}` | Unwrapped |
| PixelPass + JSON-XT | Base45 encoded URI | PixelPass decoded, then JSON-XT decoded |

#### Adapter Setup for JSON-XT

The adapter requires the `jsonxt` npm package and templates:

```bash
cd adapter/
npm install jsonxt

# Ensure templates are available
ls ../templates/jsonxt-templates.json
```

#### Startup Verification

When the adapter starts, it shows JSON-XT status:

```
===========================================
  OFFLINE-CAPABLE VERIFICATION ADAPTER
  with JSON-XT Support
===========================================

  JSON-XT: ENABLED

  Supported formats:
    - JSON-LD credentials (standard)
    - JSON-XT URIs (jxt:resolver:type:version:data)
```

If you see `JSON-XT: DISABLED`, install the jsonxt package.

#### Testing JSON-XT Verification

```bash
# 1. Issue a credential with JSON-XT output
./issue-education-credential.sh --student-name "Jane Doe" \
    --university "MIT" --degree "PhD" -q

# 2. Verify the JSON-XT file directly
JSONXT_URI=$(cat /tmp/education-credential-*-jsonxt.txt)
curl -X POST http://localhost:8085/v1/verify/vc-verification \
    -H "Content-Type: text/plain" \
    -d "$JSONXT_URI"
```

---

## Part 5: Network Topology Options

### Option A: Same Server Deployment

All components on one server:

```
┌─────────────────────────────────────────────┐
│                 Single Server               │
├─────────────────────────────────────────────┤
│  CREDEBL Agent      → localhost:8004        │
│  Adapter Service    → localhost:8085        │
│  Host Nginx         → localhost:8080        │
│  Inji verify-service → localhost:8082       │
│  Inji verify-ui     → localhost:3000        │
└─────────────────────────────────────────────┘
```

### Option B: Split Deployment (PoC Setup)

CREDEBL on local machine, Inji Verify on remote server:

```
┌─────────────────────┐         ┌─────────────────────┐
│   Local Machine     │         │   Inji Server       │
├─────────────────────┤   SSH   ├─────────────────────┤
│ CREDEBL Agent :8004 │◀───────▶│ Nginx :8080         │
│ Adapter :8085       │ Tunnel  │ verify-service:8082 │
│                     │         │ verify-ui :3000     │
└─────────────────────┘         └─────────────────────┘
```

**Automated Setup Script:**

Use the provided script to start the adapter and establish the SSH tunnel:

```bash
# Start adapter and tunnel (interactive mode)
./scripts/start-adapter-tunnel.sh \
  --server 159.89.164.7 \
  --api-key "your-credebl-api-key"

# Or run in background (daemon mode)
./scripts/start-adapter-tunnel.sh \
  --server 159.89.164.7 \
  --api-key "your-credebl-api-key" \
  --background

# Check status
./scripts/start-adapter-tunnel.sh --status

# Stop services
./scripts/start-adapter-tunnel.sh --stop
```

**Script Features:**
- Validates CREDEBL agent connectivity before starting
- Tests SSH connection before establishing tunnel
- Auto-reconnects if tunnel drops (in foreground mode)
- Cleans up stale processes on remote server
- Provides health monitoring and status checking

**Environment Variables (alternative to CLI options):**
```bash
export INJI_SERVER=159.89.164.7
export INJI_USER=root
export CREDEBL_API_KEY="your-api-key"
export CREDEBL_AGENT_URL=http://localhost:8004
./scripts/start-adapter-tunnel.sh
```

**Manual SSH Tunnel (if not using the script):**
```bash
ssh -R 8085:localhost:8085 user@inji-server -o ServerAliveInterval=30
```

### Option C: Production Deployment

```
┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐
│  Load Balancer   │───▶│  CREDEBL Cluster │───▶│  Polygon RPC     │
│  (HTTPS :443)    │    │  (K8s/Docker)    │    │  (Infura/Alchemy)│
└──────────────────┘    └──────────────────┘    └──────────────────┘
         │
         ▼
┌──────────────────┐    ┌──────────────────┐
│  Inji Verify     │───▶│  Adapter Service │
│  (K8s/Docker)    │    │  (Sidecar/Pod)   │
└──────────────────┘    └──────────────────┘
```

---

## Part 6: Verification Flow

### 6.1 Complete Request Flow

1. **User scans QR code** with Inji Verify UI
2. **verify-ui decodes** PixelPass data to get credential JSON
3. **verify-ui sends** POST to `/v1/verify/vc-verification`
4. **verify-ui nginx** proxies to host nginx (172.18.0.1:8080)
5. **Host nginx** proxies to adapter (localhost:8085)
6. **Adapter** authenticates with CREDEBL agent
7. **Adapter** calls CREDEBL `/agent/credential/verify`
8. **CREDEBL agent** resolves `did:polygon` from Polygon blockchain
9. **CREDEBL agent** verifies signature using on-chain public key
10. **Adapter** maps response to Inji format
11. **Result** propagates back to UI: `{"verificationStatus": "SUCCESS"}`

### 6.2 API Request/Response Examples

**Inji Verify Request:**
```json
POST /v1/verify/vc-verification
{
  "credential": {
    "@context": ["https://www.w3.org/2018/credentials/v1", ...],
    "type": ["VerifiableCredential", "EmploymentCredential"],
    "issuer": "did:polygon:0xD3A288e4cCeb5ADE57c5B674475d6728Af3bD9Fd",
    "credentialSubject": { ... },
    "proof": {
      "type": "EcdsaSecp256k1Signature2019",
      "jws": "eyJhbGci..."
    }
  }
}
```

**CREDEBL Agent Response:**
```json
{
  "isValid": true,
  "results": [...]
}
```

**Adapter Response (Inji format):**
```json
{
  "verificationStatus": "SUCCESS"
}
```

---

## Part 7: Troubleshooting

### 7.1 Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| `INVALID` verification | Signature mismatch | Ensure DID document on-chain has correct publicKeyBase58 |
| `504 Gateway Timeout` | Adapter unreachable | Check SSH tunnel or adapter service status |
| `No credentials found` | Wrong request format | Adapter expects `credential` or `verifiableCredentials` field |
| DID resolution fails | RPC endpoint issue | Verify Polygon RPC URL is accessible |
| Agent crashes with "password authentication failed" | Postgres password mismatch | Reset postgres password (see section 7.4) |
| Agent container exits immediately | Database connection error | Check postgres is running and password is correct |

### 7.2 Debugging Commands

```bash
# Check adapter health
curl http://localhost:8085/health

# Test verification directly
curl -X POST http://localhost:8085/v1/verify/vc-verification \
  -H "Content-Type: application/json" \
  -d '{"credential": {...}}'

# Check CREDEBL agent
curl -H "Authorization: YOUR_KEY" http://localhost:8004/agent

# View adapter logs
docker logs credebl-inji-adapter

# Check nginx routing
curl -v http://localhost:8080/v1/verify/vc-verification
```

### 7.3 Verifying the DID Document

```bash
# Resolve DID from Polygon
curl "https://resolver.identity.foundation/1.0/identifiers/did:polygon:mainnet:YOUR_ADDRESS"

# Or via CREDEBL agent
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8004/dids/did:polygon:YOUR_ADDRESS"
```

### 7.4 Database Connection Issues

The AFJ (Aries Framework JavaScript) agent stores wallet data in PostgreSQL. If the agent fails to start with a "password authentication failed" error, follow these steps:

**Symptoms:**
```
WalletError: Error opening wallet TestaIssuer002Wallet: Error connecting to database pool
Caused by: error returned from database: password authentication failed for user "postgres"
```

**Diagnosis:**
```bash
# Check postgres container logs for authentication failures
sudo docker logs credebl-postgres 2>&1 | grep "password authentication failed"

# Check if agent container is running
sudo docker ps -a | grep agent

# View agent crash logs
sudo docker logs <agent-container-name> --tail 50
```

**Solution - Reset PostgreSQL Password:**

```bash
# Connect to postgres container and reset password
sudo docker exec credebl-postgres psql -U postgres -c "ALTER USER postgres PASSWORD 'postgres';"

# Verify connection works from another container
sudo docker run --rm --network docker-deployment_default postgres:16 \
  psql 'postgresql://postgres:postgres@credebl-postgres:5432/credebl' -c 'SELECT 1'

# Restart the failed agent container
sudo docker start <agent-container-name>

# Check agent logs for successful startup
sudo docker logs <agent-container-name> --tail 20
```

**Root Cause:**

This issue typically occurs when:
1. The postgres container was initialized with a different password
2. The container data volume was reused but environment variables changed
3. The `pg_hba.conf` uses `scram-sha-256` authentication but the password hash doesn't match

**Prevention:**

Ensure the `POSTGRES_PASSWORD` environment variable in docker-compose matches what's stored in the postgres data volume. If starting fresh, remove the postgres volume first:

```bash
sudo docker-compose down -v  # Warning: This deletes all data
sudo docker-compose up -d
```

---

## Part 8: Security Considerations

### 8.1 Production Recommendations

1. **TLS/HTTPS**: Enable HTTPS on all endpoints
2. **API Key Rotation**: Rotate CREDEBL API keys regularly
3. **Network Isolation**: Place adapter in private network, expose only through load balancer
4. **Rate Limiting**: Add rate limiting to verification endpoint
5. **Audit Logging**: Log all verification requests for compliance

### 8.2 Private Key Management

- Never commit private keys to version control
- Use environment variables or secrets management (Vault, AWS Secrets Manager)
- Consider HSM for production key storage

---

## Appendix A: File Listing

```
/patches/polygon-did-fix/
├── README.md                        # Overview and quick start
├── POC-DEPLOYMENT-GUIDE.md          # This document
├── docker-compose.adapter.yml       # Docker Compose for adapter
├── adapter/
│   ├── adapter.js                   # Adapter service source
│   ├── package.json                 # Node.js dependencies
│   └── Dockerfile                   # Container build file
├── nginx/
│   ├── inji-adapter.conf            # Host nginx config
│   └── verify-ui-nginx.conf.template # Container nginx template
└── scripts/
    ├── setup-inji-routing.sh        # Inji Verify routing setup
    └── start-adapter-tunnel.sh      # Adapter + SSH tunnel startup
```

## Appendix B: Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ADAPTER_PORT` | Adapter listen port | 8085 |
| `CREDEBL_AGENT_URL` | CREDEBL agent base URL | http://localhost:8004 |
| `CREDEBL_API_KEY` | Agent API authentication key | (required) |

## Appendix C: Version Compatibility

| Component | Tested Version |
|-----------|----------------|
| CREDEBL Platform | 2.x |
| Credo-TS Agent | 0.5.x |
| Inji Verify UI | develop |
| Inji Verify Service | develop |
| Node.js | 20.x |
| Nginx | 1.24.x |
| @injistack/pixelpass | 0.8.0-RC2 |

---

## Summary

This PoC demonstrates that CREDEBL can issue W3C Verifiable Credentials on Polygon blockchain, and Inji Verify can verify them through a lightweight adapter service. The adapter translates between Inji's API format and CREDEBL's verification API, enabling interoperability without modifying either platform's core code.

**Key Achievement**: Blockchain-anchored DIDs (`did:polygon`) with `EcdsaSecp256k1Signature2019` proofs are now verifiable through Inji Verify's standard QR scanning interface.
