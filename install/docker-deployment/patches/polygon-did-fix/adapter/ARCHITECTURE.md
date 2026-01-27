# Verification Adapter Architecture

## Overview

The verification adapter is a Node.js service that bridges Inji Verify UI to multiple verification backends. It provides automatic format detection, credential decoding, and intelligent routing.

## High-Level Architecture

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

## Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                            INPUT FORMAT DETECTION                                │
└─────────────────────────────────────────────────────────────────────────────────┘

  Raw Input
      │
      ▼
  ┌───────────────────┐
  │ Is PixelPass?     │──── Yes ───▶ pixelpass.decode() ───┐
  │ /^[A-Z0-9 $%*+./  │                                    │
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
  │ startsWith('{')   │                │        │ Is JSON-XT?     │─── Yes ──▶ jsonxt.decode()
  └─────────┬─────────┘                │        │ startsWith      │                │
            │ Yes                      │        │ ('jxt:')        │                │
            ▼                          │        └────────┬────────┘                │
  ┌───────────────────┐                │                 │ No                      │
  │ JSON.parse()      │                │                 ▼                         │
  └─────────┬─────────┘                │        ┌─────────────────┐                │
            │                          │        │ JSON.parse()    │                │
            ▼                          ▼        └────────┬────────┘                │
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

## Component Details

### 1. PixelPass Decoder

```
┌─────────────────────────────────────────────────────┐
│              @mosip/pixelpass                        │
├─────────────────────────────────────────────────────┤
│                                                     │
│  Input:  NCFF-J91S7MJ.20T9KC-RIKQ:K88OUD04M8EP...  │
│          (Base45 encoded, zlib compressed)          │
│                                                     │
│  Process:                                           │
│    1. Base45 decode                                 │
│    2. Zlib decompress                               │
│                                                     │
│  Output: jxt:local:educ:1:did%3Apolygon%3A0x...    │
│          (or raw JSON-LD credential)                │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### 2. JSON-XT Decoder

```
┌─────────────────────────────────────────────────────┐
│                    jsonxt                            │
├─────────────────────────────────────────────────────┤
│                                                     │
│  Input:  jxt:local:educ:1:did%3Apolygon%3A0x.../   │
│          1KNIDMD/did%3Aexample.../Name/Univ/...    │
│                                                     │
│  URI Format:                                        │
│    jxt:<resolver>:<type>:<version>:<data>          │
│                                                     │
│  Templates (jsonxt-templates.json):                 │
│    - educ: Education Credential template            │
│    - Maps compressed fields to JSON-LD structure    │
│                                                     │
│  Output: Full JSON-LD Verifiable Credential        │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### 3. Verification Router

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          VERIFICATION ROUTER                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  credential.issuer                                                          │
│        │                                                                    │
│        ▼                                                                    │
│  ┌─────────────────┐                                                       │
│  │ Extract DID     │                                                       │
│  │ Method          │                                                       │
│  └────────┬────────┘                                                       │
│           │                                                                 │
│           ├─── did:polygon:* ───▶ CREDEBL Agent ───▶ Polygon RPC           │
│           │                       POST /agent/credential/verify             │
│           │                       Authorization: Bearer <JWT>               │
│           │                                                                 │
│           ├─── did:web:* ───────▶ Inji Verify Service                      │
│           │                       POST /v1/verify/vc-verification           │
│           │                                                                 │
│           ├─── did:key:* ───────▶ Inji Verify Service                      │
│           │                                                                 │
│           └─── did:jwk:* ───────▶ Inji Verify Service                      │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Offline Mode Support

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           CONNECTIVITY MODES                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                         ONLINE MODE                                  │   │
│  │                                                                      │   │
│  │   • Upstream services reachable                                     │   │
│  │   • Routes to CREDEBL Agent or Inji Verify Service                  │   │
│  │   • Caches issuer DID documents for offline use                     │   │
│  │                                                                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                         OFFLINE MODE                                 │   │
│  │                                                                      │   │
│  │   • Upstream services unreachable                                   │   │
│  │   • Uses SQLite cache for issuer public keys                        │   │
│  │   • Local signature verification (Ed25519, secp256k1)               │   │
│  │   • Limited to previously cached issuers                            │   │
│  │                                                                      │   │
│  │   Cache Structure (SQLite):                                         │   │
│  │   ┌─────────────────────────────────────────────────────────┐      │   │
│  │   │ issuers                                                  │      │   │
│  │   │ ├── did (PRIMARY KEY)                                   │      │   │
│  │   │ ├── publicKeyHex                                        │      │   │
│  │   │ ├── keyType (Ed25519 | secp256k1)                       │      │   │
│  │   │ ├── didDocument (JSON)                                  │      │   │
│  │   │ ├── cachedAt                                            │      │   │
│  │   │ └── expiresAt                                           │      │   │
│  │   └─────────────────────────────────────────────────────────┘      │   │
│  │                                                                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## API Endpoints

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           ADAPTER ENDPOINTS                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  POST /v1/verify/vc-verification                                           │
│  ├── Content-Type: application/json      → JSON-LD credential              │
│  ├── Content-Type: application/vc+ld+json → JSON-LD credential             │
│  ├── Content-Type: text/plain            → JSON-XT URI or PixelPass        │
│  └── Response: { verificationStatus, vc, online, backend, details }        │
│                                                                             │
│  POST /verify-offline                                                       │
│  └── Force offline verification (uses cache only)                          │
│                                                                             │
│  POST /sync                                                                 │
│  └── Sync issuer(s) to cache: { "issuers": ["did:polygon:0x..."] }        │
│                                                                             │
│  GET /cache                                                                 │
│  └── View cache statistics and cached issuers                              │
│                                                                             │
│  GET /health                                                                │
│  └── Health check with connectivity and cache status                       │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Dependencies

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              DEPENDENCIES                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  @mosip/pixelpass    │ Decode PixelPass QR data (base45 + zlib)            │
│  jsonxt              │ Decode JSON-XT compressed credentials                │
│  better-sqlite3      │ SQLite for offline issuer cache                      │
│                                                                             │
│  Node.js built-ins:                                                         │
│  http/https          │ HTTP server and client                               │
│  crypto              │ Signature verification (Ed25519, secp256k1)          │
│  fs/path             │ File system operations                               │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Example Request/Response

```
REQUEST:
────────
POST /v1/verify/vc-verification HTTP/1.1
Content-Type: text/plain

NCFF-J91S7MJ.20T9KC-RIKQ:K88OUD04M8EP8FAPR33F...

ADAPTER PROCESSING:
───────────────────
[ADAPTER] Detected PixelPass-encoded data, decoding...
[PIXELPASS] Decoding data...
[PIXELPASS] Decoded to: jxt:local:educ:1:did%3Apolygon%3A0xD3A288e4cCeb5AD...
[ADAPTER] Detected JSON-XT URI in request body
[JSONXT] Decoding URI: jxt:local:educ:1:did%3Apolygon%3A0xD3A288e4cCeb5AD...
[JSONXT] Decoded credential from issuer: did:polygon:0xD3A288e4cCeb5ADE57c5B674475d6728Af3bD9Fd
[ADAPTER] Processing credential from issuer: did:polygon:0xD3A288e4cCeb5ADE57c5B674475d6728Af3bD9Fd
[VERIFY] Credential from issuer: did:polygon:..., method: did:polygon, proof: EcdsaSecp256k1Signature2019
[VERIFY] Mode: ONLINE

RESPONSE:
─────────
HTTP/1.1 200 OK
Content-Type: application/json

{
  "verificationStatus": "SUCCESS",
  "online": true,
  "backend": "credebl-agent",
  "vc": {
    "@context": ["https://www.w3.org/2018/credentials/v1", ...],
    "type": ["VerifiableCredential", "EducationCredential"],
    "issuer": "did:polygon:0xD3A288e4cCeb5ADE57c5B674475d6728Af3bD9Fd",
    "credentialSubject": {
      "name": "Lamar Odom",
      "alumniOf": "Spike University",
      "degree": "Physical Training",
      "fieldOfStudy": "Basketballing",
      "studentId": "BBALL001"
    },
    "proof": { ... }
  },
  "verifiableCredential": { ... same as vc ... },
  "details": {
    "isValid": true,
    "validations": { ... }
  }
}
```
