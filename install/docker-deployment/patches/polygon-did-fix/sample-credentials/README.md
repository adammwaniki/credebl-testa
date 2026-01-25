# Sample Credentials for Testing

This directory contains sample W3C Verifiable Credentials for testing the verification adapter.

## Credential Types

### did:indy Credentials (W3C JSON-LD format)

| File | Issuer DID | Network | Proof Type |
|------|------------|---------|------------|
| `did-indy-education-credential.json` | `did:indy:bcovrin:testnet:3avoBCqDMFHFaKUHug9s8W` | BCovrin Testnet | Ed25519Signature2020 |
| `did-indy-employment-credential.json` | `did:indy:indicio:testnet:WgWxqztrNooG92RXvxSTWv` | Indicio Testnet | Ed25519Signature2018 |

## Important Notes

**These are MOCK credentials** with invalid signatures. They are designed to:

1. Test adapter **routing logic** (did:indy → CREDEBL Agent)
2. Verify **credential structure parsing**
3. Test **error handling** for unknown issuers

**For real verification**, you need:
- A registered did:indy DID on the ledger (BCovrin, Indicio, etc.)
- Credentials signed by that DID's private key
- The issuer synced to the adapter cache

## Testing Commands

### Test Adapter Routing (Mock Credentials)

```bash
# Verify mock credential through adapter
curl -X POST http://localhost:8085/v1/verify/vc-verification \
  -H "Content-Type: application/json" \
  -d @did-indy-education-credential.json

# Expected: Routes to CREDEBL Agent, returns INVALID or UNKNOWN_ISSUER
```

### Test with Real Credentials

1. **Create a did:indy organization in CREDEBL** (via Studio UI or API)
2. **Issue a W3C credential** using the test script:
   ```bash
   ../test-indy-credential.sh --mode issue \
     -d "did:indy:bcovrin:testnet:YOUR_DID" \
     --name "Test User" \
     -v -q
   ```

### Sync Issuer to Cache

```bash
# Sync a known issuer for trusted verification
curl -X POST http://localhost:8085/sync \
  -H "Content-Type: application/json" \
  -d '{"did": "did:indy:bcovrin:testnet:YOUR_DID"}'
```

## Supported Indy Networks

| Network | Namespace | Self-Service Registration |
|---------|-----------|--------------------------|
| BCovrin Testnet | `bcovrin:testnet` | http://test.bcovrin.vonx.io/register |
| Indicio Testnet | `indicio:testnet` | https://selfserve.indiciotech.io/nym |
| Indicio Demonet | `indicio:demonet` | https://selfserve.indiciotech.io/nym |
| Indicio Mainnet | `indicio:mainnet` | https://selfserve.indiciotech.io/nym |

## Credential Format Requirements

For Inji Verify compatibility, credentials must be:

- **Format**: W3C JSON-LD (`LDP_VC`) - NOT native AnonCreds
- **Proof Types**: Ed25519Signature2018, Ed25519Signature2020, or EcdsaSecp256k1Signature2019
- **Context**: Must include `https://www.w3.org/2018/credentials/v1`

Native AnonCreds (Hyperledger Indy's original format) are **not supported** by Inji Verify.
