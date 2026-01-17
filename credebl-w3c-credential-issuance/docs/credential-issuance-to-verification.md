# Credential Issuance to Inji Verify: Quick Guide

This guide covers the process from issuing a W3C JSON-LD Verifiable Credential to generating a scannable QR code for Inji Verify.

## Prerequisites

- Running credo-controller agent with an active connection to a holder wallet
- Node.js installed (for PixelPass encoding)
- `qrencode` package installed
- `@injistack/pixelpass` npm package installed

## Overview

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Issue          │────▶│  Retrieve       │────▶│  Encode with    │────▶│  Scan with      │
│  Credential     │     │  Signed VC      │     │  PixelPass      │     │  Inji Verify    │
└─────────────────┘     └─────────────────┘     └─────────────────┘     └─────────────────┘
```

## Step 1: Issue Credential to Connected Holder

### Get Authentication Token

```bash
# Get JWT token from agent
JWT=$(curl -s -X POST http://localhost:8003/agent/token \
  -H "authorization: YOUR_API_KEY" | jq -r '.token')
```

### Issue the Credential

```bash
curl -X POST http://localhost:8003/didcomm/credentials/create-offer \
  -H "authorization: $JWT" \
  -H "Content-Type: application/json" \
  -d '{
    "connectionId": "YOUR_CONNECTION_ID",
    "protocolVersion": "v2",
    "credentialFormats": {
      "jsonld": {
        "credential": {
          "@context": [
            "https://www.w3.org/2018/credentials/v1",
            "https://www.w3.org/2018/credentials/examples/v1"
          ],
          "type": ["VerifiableCredential", "EmploymentCredential"],
          "issuer": "YOUR_ISSUER_DID",
          "issuanceDate": "2026-01-15T00:00:00Z",
          "credentialSubject": {
            "id": "HOLDER_DID",
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
  }'
```

### Wait for Credential Exchange to Complete

```bash
# Check credential status (should be "done")
curl -s -H "authorization: $JWT" \
  http://localhost:8003/didcomm/credentials/CREDENTIAL_RECORD_ID | jq '.state'
```

## Step 2: Retrieve Signed Credential

```bash
# Get the signed credential with proof
curl -s -H "authorization: $JWT" \
  http://localhost:8003/didcomm/credentials/CREDENTIAL_RECORD_ID/form-data \
  | jq '.credential.jsonld' > credential.json
```

The signed credential will look like:

```json
{
  "@context": [
    "https://www.w3.org/2018/credentials/v1",
    "https://www.w3.org/2018/credentials/examples/v1"
  ],
  "type": ["VerifiableCredential", "EmploymentCredential"],
  "issuer": "did:key:z6Mk...",
  "issuanceDate": "2026-01-15T00:00:00Z",
  "credentialSubject": {
    "id": "did:peer:1z...",
    "employeeOf": {
      "name": "Organization Name",
      "position": "Job Title",
      "startDate": "2024-01-01"
    }
  },
  "proof": {
    "type": "Ed25519Signature2018",
    "created": "2026-01-15T00:00:00Z",
    "verificationMethod": "did:key:z6Mk...#z6Mk...",
    "proofPurpose": "assertionMethod",
    "jws": "eyJhbGciOiJFZERTQSIs..."
  }
}
```

## Step 3: Encode with PixelPass

Inji Verify requires credentials to be encoded using **PixelPass** (CBOR compression format).

### Install PixelPass

```bash
npm install @injistack/pixelpass
```

### Encode the Credential

```bash
node -e "
const { generateQRData } = require('@injistack/pixelpass');
const fs = require('fs');
const credential = JSON.parse(fs.readFileSync('credential.json', 'utf8'));
process.stdout.write(generateQRData(JSON.stringify(credential)));
" > qrdata.txt
```

The encoded data will look like:

```
NCFH-JL:PNMJXQ2V2C.NL6-I5:78EK9I97GQGS8R9C/GI4I1Q9DD%06O3+FBSM2...
```

## Step 4: Generate QR Code

### As PNG Image

```bash
qrencode -o credential-qr.png -s 10 -m 2 < qrdata.txt
```

### As Terminal Output

```bash
qrencode -t ANSIUTF8 < qrdata.txt
```

## Step 5: Scan with Inji Verify

1. Open Inji Verify app or web interface
2. Select "Scan QR Code"
3. Point camera at the QR code
4. Verification result will display

## Important Notes

### Inji Verify Configuration

Your credential type must be configured in Inji Verify's `config.json`:

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

### JSON-LD Context Requirements

| Context | Compatible with Ed25519Signature2018? |
|---------|--------------------------------------|
| `https://www.w3.org/2018/credentials/examples/v1` | Yes |
| `https://w3id.org/security/suites/ed25519-2018/v1` | No (protected term conflict) |
| `https://w3id.org/security/suites/ed25519-2020/v1` | No (requires Ed25519VerificationKey2020) |

### QR Code Format

| Format | Use Case |
|--------|----------|
| Raw JSON | Direct API verification only |
| `INJI_OVP://payload=...` | OpenID4VP flow (requires redirect setup) |
| PixelPass (CBOR) | Inji Verify QR scanning |

## Troubleshooting

### "Invalid character at position X"

- Ensure PixelPass encoding is used, not raw JSON or base64
- Verify the QR code renders cleanly (use PNG over terminal)

### "No QRCode Found"

- The QR code format is incorrect (not PixelPass encoded)
- Use `generateQRData()` from `@injistack/pixelpass`

### Verification Fails

- Check that the credential type is in Inji Verify's config
- Verify the proof type matches the config (Ed25519Signature2018)
- Test direct API verification: `POST /v1/verify/vc-verification`

## Quick Reference Commands

```bash
# Full pipeline in one command
./scripts/issue-and-generate-qr.sh CONNECTION_ID
```

See `scripts/issue-and-generate-qr.sh` for the complete automated script.
