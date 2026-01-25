# CREDEBL + Inji Verify Integration: Proof of Concept Deployment Guide

## Overview

This guide documents the integration of **CREDEBL** (for W3C Verifiable Credential issuance on blockchain) with **Inji Verify** (for credential verification). The PoC demonstrates:

1. Issuing W3C Verifiable Credentials using `did:polygon` on Polygon Mainnet
2. Verifying those credentials through Inji Verify's QR scanning interface

## Architecture

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
│  │  UI (:3000)  │    │   Service    │    │   Verification API       │  │
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

The credential issuance scripts support **JSON-XT** output - a compact representation that reduces credential size by ~45% through key mapping.

#### What is JSON-XT?

JSON-XT (JSON eXtended/Transformed) is a compression technique that:
- Maps long JSON keys to short tokens (e.g., `credentialSubject` → `cs`)
- Maps long string values like URLs to short tokens (e.g., `https://www.w3.org/2018/credentials/v1` → `w3c`)
- Maintains the same structure - just with shorter keys/values
- Requires a **mapper** to decode back to standard JSON-LD

#### Comparison: JSON-LD vs JSON-XT vs CBOR

| Format | Description | Size | Use Case |
|--------|-------------|------|----------|
| **JSON-LD** | Standard W3C VC format with semantic context | Baseline | Interoperability, verification |
| **JSON-XT** | Key-mapped JSON with short tokens | ~45% smaller | Storage, transmission |
| **CBOR** | Binary encoding (used inside PixelPass QR) | ~60% smaller | QR codes, IoT |

#### Credential Key Mappers

##### Education Credential Mapper

The `issue-education-credential.sh` script uses this mapper:

```javascript
const educationCredentialMapper = {
    // W3C VC standard fields
    '@context': 'x',
    'type': 't',
    'id': 'i',
    'issuer': 'is',
    'issuanceDate': 'idt',
    'credentialSubject': 'cs',
    'proof': 'p',

    // Proof fields
    'verificationMethod': 'vm',
    'proofPurpose': 'pp',
    'proofValue': 'pv',
    'created': 'cr',
    'jws': 'jw',

    // Education credential fields
    'EducationCredential': 'EC',
    'VerifiableCredential': 'VC',
    'name': 'n',
    'alumniOf': 'ao',
    'degree': 'd',
    'fieldOfStudy': 'fs',
    'enrollmentDate': 'ed',
    'graduationDate': 'gd',
    'studentId': 'si',
    'gpa': 'g',
    'honors': 'h',

    // Schema.org URLs
    'https://www.w3.org/2018/credentials/v1': 'w3c',
    'https://schema.org/EducationalOccupationalCredential': 's:eoc',

    // Signature types
    'EcdsaSecp256k1Signature2019': 'ES256K',
    'Ed25519Signature2018': 'EdDSA18',
    'Ed25519Signature2020': 'EdDSA20',
    'assertionMethod': 'am'
};
```

##### Employment Credential Mapper

The `issue-employment-credential.sh` script uses this mapper:

```javascript
const employmentCredentialMapper = {
    // W3C VC standard fields
    '@context': 'x',
    'type': 't',
    'id': 'i',
    'issuer': 'is',
    'issuanceDate': 'idt',
    'expirationDate': 'edt',
    'credentialSubject': 'cs',
    'proof': 'p',

    // Proof fields
    'verificationMethod': 'vm',
    'proofPurpose': 'pp',
    'proofValue': 'pv',
    'created': 'cr',
    'jws': 'jw',

    // Employment credential fields
    'EmploymentCredential': 'EmC',
    'VerifiableCredential': 'VC',
    'employeeName': 'en',
    'employerName': 'er',
    'jobTitle': 'jt',
    'department': 'dp',
    'dateOfJoining': 'doj',
    'employeeId': 'eid',
    'employmentType': 'et',

    // Schema.org URLs
    'https://www.w3.org/2018/credentials/v1': 'w3c',
    'https://schema.org/EmployeeRole': 's:er',
    'https://schema.org/name': 's:n',
    'https://schema.org/legalName': 's:ln',
    'https://schema.org/jobTitle': 's:jt',
    'https://schema.org/department': 's:dp',
    'https://schema.org/startDate': 's:sd',
    'https://schema.org/identifier': 's:id',
    'https://schema.org/employmentType': 's:et',

    // Signature types
    'EcdsaSecp256k1Signature2019': 'ES256K',
    'Ed25519Signature2018': 'EdDSA18',
    'Ed25519Signature2020': 'EdDSA20',
    'assertionMethod': 'am'
};
```

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

**Output files (both scripts):**
```
/tmp/<type>-credential-*.json        # Original JSON-LD
/tmp/<type>-credential-*-jsonxt.json # Compact JSON-XT
/tmp/<type>-credential-*-mapper.json # Key mapper for decoding
/tmp/<type>-credential-*-qr.png      # QR code image
/tmp/<type>-credential-*-qr.txt      # QR data (base45 encoded)
```

#### Example Size Comparison

| Credential | JSON-LD | JSON-XT | Reduction |
|------------|---------|---------|-----------|
| Education Credential | 1,388 bytes | 760 bytes | 45.2% |
| Employment Credential | 1,245 bytes | 685 bytes | 45.0% |

#### Important Notes

1. **Verification uses JSON-LD**: Inji Verify expects standard JSON-LD format. JSON-XT is for storage/transmission only.
2. **PixelPass uses CBOR internally**: The QR code is encoded from JSON-LD using zlib → CBOR → base45.
3. **Mapper must be preserved**: To decode JSON-XT back to JSON-LD, you need the mapper file.
4. **Custom mappers**: Create credential-type-specific mappers for maximum compression.

#### Implementation Reference

The JSON-XT mappers are implemented in the credential issuance scripts:

| Credential Type | Script | Mapper Variable |
|-----------------|--------|-----------------|
| Education | `issue-education-credential.sh` | `educationCredentialMapper` (lines 377-428) |
| Employment | `issue-employment-credential.sh` | `employmentCredentialMapper` (lines 327-378) |

**File locations:**
```
patches/polygon-did-fix/
├── issue-education-credential.sh    # Education credential with JSON-XT
├── issue-employment-credential.sh   # Employment credential with JSON-XT
└── POC-DEPLOYMENT-GUIDE.md          # This documentation
```

**Creating custom mappers:**

To create a JSON-XT mapper for a new credential type:

1. Identify all keys and string values in your credential
2. Create short tokens (1-3 chars) for each
3. Include standard W3C VC fields (@context, type, proof, etc.)
4. Include schema.org URL mappings if using schema.org vocabulary
5. Store the mapper alongside the credential for decoding

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
