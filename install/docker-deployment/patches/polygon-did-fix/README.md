# Polygon DID W3C Credential Issuance Fix

## Overview

This document describes the process of enabling W3C Verifiable Credential issuance using `did:polygon` DIDs on the CREDEBL platform. The work started from a working `did:key` implementation and required several patches to the `@ayanworks/credo-polygon-w3c-module` to support polygon DID signing.

---

## Background

### Starting Point: did:key Works

The CREDEBL platform successfully issues W3C credentials using `did:key`:
- `did:key` DIDs are generated locally without blockchain interaction
- Credentials are signed using Ed25519 keys
- No patches required - works out of the box

### Goal: did:polygon Support

Enable credential issuance using `did:polygon` DIDs:
- DIDs registered on Polygon Mainnet blockchain
- Credentials signed using secp256k1 keys (ECDSA)
- Proof type: `EcdsaSecp256k1Signature2019`

---

## Problems Encountered and Solutions

### Problem 1: "Key already exists" Error

**Symptom:** When trying to register a polygon DID with an existing private key, the agent crashed with "Key already exists in wallet".

**Root Cause:** The `PolygonDidRegistrar.create()` method tried to create a new key without checking if it already existed.

**Solution:** Added try-catch to handle existing keys by deriving the public key from the private key:
```javascript
try {
    key = await agentContext.wallet.createKey({ keyType: KeyType.K256, privateKey });
} catch (error) {
    if (errorMessage.includes('key already exists')) {
        // Derive key from private key instead
        const signingKey = new SigningKey(privateKeyHex);
        const publicKeyBuffer = Buffer.from(signingKey.compressedPublicKey.slice(2), 'hex');
        key = Key.fromPublicKey(publicKeyBuffer, KeyType.K256);
    }
}
```

### Problem 2: Invalid DID Format

**Symptom:** DID validation failed with "Invalid DID" error when resolving `did:polygon:mainnet:0xADDRESS`.

**Root Cause:** The underlying `@ayanworks/polygon-did-resolver` only accepts `did:polygon:0xADDRESS` format (without network prefix), but the API was sending `did:polygon:mainnet:0xADDRESS`.

**Solution:**
1. Updated `didPolygonUtil.js` regex to accept both formats
2. Transform DID format before passing to resolver: `did.replace(':mainnet:', ':')`

### Problem 3: Wallet Session Access Error

**Symptom:** "Cannot read properties of undefined (reading 'fetch')" when trying to sign.

**Root Cause:** Incorrect wallet session access pattern.

**Solution:** Changed from `wallet.session.fetch()` to `wallet.withSession()`:
```javascript
const keyEntry = await wallet.withSession(async (session) => {
    return session.fetchKey({ name: publicKeyBase58 });
});
```

### Problem 4: DID Document Missing publicKeyBase58

**Symptom:** Blockchain returns DID document with `blockchainAccountId` instead of `publicKeyBase58`, which Credo requires for signing.

**Root Cause:** The polygon blockchain stores verification methods with `blockchainAccountId` format, not `publicKeyBase58`.

**Solution:** Store DID document locally with `publicKeyBase58` format and use `allowsLocalDidRecord = true` to prefer local records over blockchain resolution.

### Problem 5: "verification method is missing publicKeyBase58" (THE MAIN FIX)

**Symptom:** Even with local DID record containing `publicKeyBase58`, credential signing failed with this error.

**Root Cause:** During signing, Credo uses JSON-LD `frame()` to extract the verification method. The `publicKeyBase58` property was being stripped because it's not defined in the basic `https://www.w3.org/ns/did/v1` context.

**Solution:** Include the secp256k1 security context in the DID document:
```json
"@context": [
    "https://www.w3.org/ns/did/v1",
    "https://w3id.org/security/suites/secp256k1-2019/v1"
]
```

This context defines `publicKeyBase58` as a valid JSON-LD term, preventing it from being stripped during framing.

---

## Files Modified

### 1. PolygonDidRegistrar.js
- Handle "key already exists" gracefully
- Create DID document with `publicKeyBase58` (not `blockchainAccountId`)
- Include secp256k1 security context in DID document
- Use `wallet.withSession()` for key access
- Handle "DID already registered" by importing with correct format

### 2. PolygonDidResolver.js
- Set `allowsLocalDidRecord = true` to prefer local records
- Strip URL fragment before validation
- Transform mainnet DID format for underlying resolver
- Add fallback to enrich blockchain response with local record data

### 3. didPolygonUtil.js
- Updated regex to accept mainnet prefix: `/^did:polygon(:(mainnet|testnet))?:0x[0-9a-fA-F]{40}$/`

---

## Wallet and Key Information

| Property | Value |
|----------|-------|
| DID | `did:polygon:0xD3A288e4cCeb5ADE57c5B674475d6728Af3bD9Fd` |
| Wallet Address | `0xD3A288e4cCeb5ADE57c5B674475d6728Af3bD9Fd` |
| Private Key | `52b5fe7ac274c912b5fdd2440e846a20360d78af278d2722a79051f28b44ef3a` |
| Compressed PubKey (base58) | `f1EQ9KARWiTBFcyM74RhxhJfaS7JHSGVKxQuuq4NAXhY` |
| Uncompressed PubKey (base58) | `NXWfpPipM4TcUukdt2EbxxCEWp5vm2ucuf4fvp2x9ccRVMhWnDG8VS5tp9exmZRNpVwxWbv5yn9Gn7MEXsvCxdZf` |
| Blockchain TX | `0xe925c1a75703e674d6f7d0fea4fc023ef8175c69e3134b494fc379cda92e26af` |

---

## API Reference

### Authentication

Get JWT token (required for all other endpoints):
```bash
curl -X POST "http://localhost:8004/agent/token" \
  -H "Authorization: supersecret-that-too-16chars"
```

### Register Polygon DID
```bash
curl -X POST "http://localhost:8004/dids/write" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "method": "polygon",
    "network": "polygon:mainnet",
    "endpoint": "https://your-endpoint.com",
    "privatekey": "52b5fe7ac274c912b5fdd2440e846a20360d78af278d2722a79051f28b44ef3a"
  }'
```

### Sign W3C Credential
```bash
curl -X POST "http://localhost:8004/agent/credential/sign?storeCredential=true&dataTypeToSign=jsonLd" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "credential": {
      "@context": ["https://www.w3.org/2018/credentials/v1"],
      "type": ["VerifiableCredential"],
      "issuer": "did:polygon:0xD3A288e4cCeb5ADE57c5B674475d6728Af3bD9Fd",
      "issuanceDate": "2026-01-19T00:00:00Z",
      "credentialSubject": {
        "id": "did:example:holder",
        "name": "Test Subject"
      }
    },
    "verificationMethod": "did:polygon:0xD3A288e4cCeb5ADE57c5B674475d6728Af3bD9Fd#key-1",
    "proofType": "EcdsaSecp256k1Signature2019"
  }'
```

### Verify Credential
```bash
curl -X POST "http://localhost:8004/agent/credential/verify" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"credential": { ... signed credential ... }}'
```

---

## Usage

See the shell scripts in this directory:
- `apply-patches.sh` - Apply patches to a running container
- `check-services.sh` - Verify services are running and healthy
- `issue-credential.sh` - Issue a W3C credential with polygon DID
- `full-polygon-flow.sh` - Complete end-to-end flow

---

## Troubleshooting

### Token Expired
JWT tokens are short-lived. Get a fresh token before each operation.

### Container Restart Loses Patches
Patches are applied to container's node_modules. After restart, re-apply with `apply-patches.sh`.

### DID Format Errors
- Use `did:polygon:0xADDRESS` format (no mainnet prefix in DID)
- Use `polygon:mainnet` in the network parameter (WITH polygon: prefix)

### Missing Context Error
Ensure DID document has both contexts:
```json
"@context": [
  "https://www.w3.org/ns/did/v1",
  "https://w3id.org/security/suites/secp256k1-2019/v1"
]
```

---

## Part 2: Inji Verify Integration

This patch also includes an adapter service that bridges Inji Verify to CREDEBL for `did:polygon` credential verification.

### Why an Adapter? (Alternatives Considered)

Before choosing the adapter approach, several alternatives were evaluated:

#### Alternative 1: Patch vcverifier Library (Initially Attempted)

Inji Verify uses the `vcverifier` library for credential verification. We tried patching it to add:
- Universal Resolver support for did:polygon
- EcdsaSecp256k1Signature2019 proof type
- secp256k1 cryptographic primitives

**Why it failed:**
- Library had hardcoded algorithm checks (`ERR_INVALID_ALGORITHM`)
- Missing secp256k1 signature verification primitives
- DID resolver architecture not easily extensible
- Would require forking and maintaining a custom vcverifier

#### Alternative 2: Modify Inji Verify Service Directly

Add did:polygon support to the Java/Kotlin verify-service directly.

**Cons:**
- Significant development effort
- Need to maintain fork of Inji Verify
- Java/Kotlin expertise required
- Polygon RPC dependency in verify-service

#### Alternative 3: Universal Resolver Integration

Deploy a Universal Resolver instance that supports did:polygon.

**Why insufficient:**
- Resolves DID document ✓
- But vcverifier still can't verify `EcdsaSecp256k1Signature2019` proofs ✗
- Would need vcverifier patches anyway

#### Alternative 4: Replace Verify Service Entirely

Deploy a custom verification service replacing Inji's verify-service.

**Cons:**
- Lose Inji Verify's other features
- More to maintain
- Larger footprint

#### Chosen: Adapter Service

Bridge Inji Verify's API to CREDEBL's existing verification:

```
┌─────────────┐     ┌─────────┐     ┌─────────────┐     ┌─────────┐
│ Inji Verify │────▶│ Adapter │────▶│ CREDEBL     │────▶│ Polygon │
│ UI          │     │ ~100LOC │     │ Agent       │     │ Mainnet │
└─────────────┘     └─────────┘     └─────────────┘     └─────────┘
```

#### Comparison Matrix

| Approach | Dev Effort | Maintenance | PoC Suitable |
|----------|------------|-------------|--------------|
| Patch vcverifier | High | High (fork) | No |
| Modify verify-service | High | High (fork) | No |
| Universal Resolver | Medium | Medium | Partial |
| Replace verify-service | High | High | No |
| **Adapter** | **Low** | **Low** | **Yes** |

#### Why Adapter Won

1. **Minimal code** - ~100 lines of JavaScript
2. **No forks** - Inji Verify and CREDEBL remain unchanged
3. **Leverage existing** - CREDEBL already has working did:polygon verification
4. **Reversible** - Remove adapter, Inji Verify works as before
5. **PoC speed** - Implemented in hours, not weeks
6. **Production path** - Can later replace with native integration if needed

---

### Subject DID vs Issuer DID

**Note:** Only the **Issuer DID** needs to be `did:polygon`. The credential subject's DID can be any format:

| DID | Purpose | Must be did:polygon? |
|-----|---------|----------------------|
| **Issuer DID** | Signs the credential | **Yes** - must be resolvable for signature verification |
| **Subject DID** | Identifies credential holder | **No** - can be `did:example:`, `did:key:`, or any identifier |

The subject DID is just an identifier in the credential. It's only cryptographically verified if doing a Verifiable Presentation flow where the holder proves control of their DID.

---

### Quick Start (Same Server)

```bash
# 1. Start the adapter
cd adapter
ADAPTER_PORT=8085 CREDEBL_AGENT_URL=http://localhost:8004 CREDEBL_API_KEY=your-key node adapter.js

# 2. Configure Inji Verify routing
./scripts/setup-inji-routing.sh

# 3. Test verification
curl -X POST http://localhost:8080/v1/verify/vc-verification \
  -H "Content-Type: application/json" \
  -d '{"credential": {...}}'
```

### Quick Start (Split Deployment with SSH Tunnel)

When CREDEBL is on a local machine and Inji Verify is on a remote server:

```bash
# Start adapter and SSH tunnel with one command
./scripts/start-adapter-tunnel.sh \
  --server YOUR_INJI_SERVER_IP \
  --api-key "your-credebl-api-key"

# Or run in background
./scripts/start-adapter-tunnel.sh -s YOUR_INJI_SERVER_IP -k "your-key" -b

# Check status
./scripts/start-adapter-tunnel.sh --status

# Stop
./scripts/start-adapter-tunnel.sh --stop
```

### Directory Structure (Inji Integration)

```
polygon-did-fix/
├── POC-DEPLOYMENT-GUIDE.md            # Complete deployment documentation
├── docker-compose.adapter.yml         # Docker Compose for adapter
├── adapter/
│   ├── adapter.js                     # Adapter service source
│   ├── package.json                   # Node.js manifest
│   └── Dockerfile                     # Container build
├── nginx/
│   ├── inji-adapter.conf              # Host nginx config
│   └── verify-ui-nginx.conf.template  # Container nginx template
└── scripts/
    ├── setup-inji-routing.sh          # Inji routing setup (run on Inji server)
    └── start-adapter-tunnel.sh        # Adapter + tunnel (run locally)
```

### Full Documentation

See [POC-DEPLOYMENT-GUIDE.md](./POC-DEPLOYMENT-GUIDE.md) for comprehensive instructions on:
- CREDEBL setup for did:polygon
- Adapter service deployment
- Inji Verify modifications
- Network topology options
- QR code generation
- Troubleshooting

---

## Part 3: JSON-XT Credential Compression

### Overview

JSON-XT (Consensas format) provides significant compression for W3C Verifiable Credentials, making them suitable for QR codes. This implementation adds full JSON-XT support to the verification flow.

### Compression Benefits

| Format | Size | QR Complexity |
|--------|------|---------------|
| JSON-LD | ~1400 bytes | High density QR |
| JSON-XT | ~500 chars | **64% smaller** |
| PixelPass wrapped | ~550 chars | Scannable |

### Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    CREDENTIAL ISSUANCE WITH JSON-XT                      │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────────────┐  │
│  │  JSON-LD     │───▶│  JSON-XT     │───▶│  PixelPass Encoding      │  │
│  │  Credential  │    │  Compression │    │  (base45 + QR)           │  │
│  │  (~1400 B)   │    │  (~500 chars)│    │  (~550 chars)            │  │
│  └──────────────┘    └──────────────┘    └──────────────────────────┘  │
│                                                                          │
│  JSON-XT URI Format: jxt:local:educ:1:<issuer>/<date>/...              │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│                    VERIFICATION WITH JSON-XT SUPPORT                     │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────────────┐  │
│  │  QR Code     │───▶│  Adapter     │───▶│  CREDEBL Agent           │  │
│  │  Scan        │    │  Service     │    │  Verification            │  │
│  └──────────────┘    └──────────────┘    └──────────────────────────┘  │
│         │                   │                                           │
│         │            ┌──────┴──────┐                                   │
│         │            │             │                                   │
│         ▼            ▼             ▼                                   │
│  ┌────────────┐ ┌────────────┐ ┌────────────┐                         │
│  │ PixelPass  │ │ JSON-XT    │ │ JSON-LD    │                         │
│  │ Decode     │ │ Decode     │ │ Credential │                         │
│  │ (base45)   │ │ (jxt:...)  │ │ (verify)   │                         │
│  └────────────┘ └────────────┘ └────────────┘                         │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Adapter Processing Flow

The adapter handles multiple input formats automatically:

1. **PixelPass-encoded data** (`NCFF-...`)
   - Decoded using `@mosip/pixelpass` library
   - Result may be JSON-XT URI or JSON-LD

2. **JSON-XT URI** (`jxt:local:educ:1:...`)
   - Decoded using `jsonxt` library with local templates
   - Expands to full JSON-LD credential

3. **JSON-LD Credential** (`{"@context":...}`)
   - Passed directly to verification

```javascript
// Adapter parseRequestBody() flow:
async function parseRequestBody(body) {
    let data = body.trim();

    // Step 1: Decode PixelPass if detected
    if (isPixelPassEncoded(data)) {
        data = pixelpass.decode(data);  // NCFF-... → jxt:... or JSON
    }

    // Step 2: Decode JSON-XT if detected
    if (data.startsWith("jxt:")) {
        return { credential: await decodeJsonXt(data) };
    }

    // Step 3: Parse as JSON-LD
    return JSON.parse(data);
}
```

### SDK Modifications

The Inji Verify SDK was modified to:

1. **api.ts** - Return credential from response for JSON-XT:
   ```typescript
   // Returns full response when credential is decoded by adapter
   if (data.vc || data.verifiableCredential) {
     return {
       verificationStatus: data.verificationStatus,
       vc: data.vc || data.verifiableCredential
     };
   }
   return data.verificationStatus;
   ```

2. **QRCodeVerification.tsx** - Use response credential for display:
   ```typescript
   const result = await vcVerification(vc, verifyServiceUrl);
   // Handle JSON-XT response which includes decoded credential
   let vcToDisplay = vc;
   let vcStatus = result;
   if (typeof result === "object" && result.verificationStatus) {
     vcStatus = result.verificationStatus;
     if (result.vc) {
       vcToDisplay = result.vc;  // Use adapter-decoded credential
     }
   }
   onVCProcessed([{ vc: vcToDisplay, vcStatus: vcStatus }]);
   ```

### Configuration

Add credential types to `config.json` for UI display:

```json
{
  "verifiableClaims": [
    {
      "logo": "/assets/cert.png",
      "name": "Education Credential",
      "type": "EducationCredential",
      "clientIdScheme": "did",
      "definition": {
        "purpose": "Verification of educational qualifications",
        "format": {
          "ldp_vc": {
            "proof_type": ["EcdsaSecp256k1Signature2019"]
          }
        }
      }
    }
  ],
  "VCRenderOrders": {
    "EducationCredentialRenderOrder": [
      "name",
      "alumniOf",
      "degree",
      "fieldOfStudy",
      "enrollmentDate",
      "graduationDate",
      "studentId",
      "gpa",
      "honors"
    ]
  }
}
```

### Dependencies

The adapter requires these npm packages:

```json
{
  "dependencies": {
    "@mosip/pixelpass": "^0.6.0",
    "better-sqlite3": "^11.0.0",
    "jsonxt": "^0.0.19"
  }
}
```

### Issuing JSON-XT Credentials

Use the `issue-education-credential.sh` script:

```bash
./issue-education-credential.sh -v -q
# Follow prompts for student details
# Outputs:
#   - JSON-LD credential file
#   - JSON-XT URI file
#   - QR code image (PixelPass wrapped)
```

### Testing

```bash
# Test with JSON-XT URI directly
curl -X POST http://localhost:8085/v1/verify/vc-verification \
  -H "Content-Type: text/plain" \
  -d "jxt:local:educ:1:did%3Apolygon%3A0x..."

# Test with PixelPass-encoded QR data
curl -X POST http://localhost:8085/v1/verify/vc-verification \
  -H "Content-Type: text/plain" \
  -d "NCFF-J91S7MJ..."

# Response includes credential for UI display:
{
  "verificationStatus": "SUCCESS",
  "vc": {
    "@context": [...],
    "credentialSubject": {
      "name": "Student Name",
      "degree": "Bachelor of Science",
      ...
    }
  }
}
```
