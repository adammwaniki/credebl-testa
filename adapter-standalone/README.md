# Verification Adapter

A backend-agnostic verification adapter that sits between any credential verification UI and any W3C-compliant verifier backend, with standards-compliant offline cryptographic verification. Adding a new backend (CREDEBL, walt.id, Inji Verify, or custom) is a JSON config change — no code modification.

## Why it matters

Verification adapters in CREDEBL, walt.id, and MOSIP stacks are coupled to their respective backend APIs — hardcoded endpoints, auth flows, request formats, and DID method routing. When the deployment target changes, the adapter must be rewritten. This adapter treats backends as configuration: a `Backend` interface and `backends.json` file let operators add, remove, or re-prioritise verifier backends without rebuilding the binary.

Offline verification uses URDNA2015 JSON-LD canonicalization with the W3C Data Integrity two-hash pattern (`SHA256(canon(proofOpts)) || SHA256(canon(doc))`), enabling cryptographic signature verification without network access to any backend.

## What it does

| Capability | Detail |
| --- | --- |
| Online verification | Routes credentials to the correct backend by DID method, with per-backend auth, request wrapping, and response parsing |
| Offline verification | Caches issuer public keys via `/sync`, verifies Ed25519 and RSA signatures locally using URDNA2015 canonicalization |
| Backend routing | `BackendRegistry.Select(didMethod)` — config-driven, priority-ordered |
| Input decoding | PixelPass (Base45 + zlib), JSON-XT template expansion, raw JSON-LD |
| DID resolution | did:key (local), did:web (HTTPS), did:polygon (Ethereum RPC) |
| Proof types | Ed25519Signature2018/2020, EcdsaSecp256k1Signature2019, RsaSignature2018, DataIntegrityProof/eddsa-rdfc-2022 |

### Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| POST | `/v1/verify/vc-verification` | Verify credential (auto online/offline) |
| POST | `/verify-offline` | Force offline verification |
| POST | `/sync` | Cache issuer DID(s) for offline use |
| GET | `/cache` | Cache statistics |
| GET | `/templates` | JSON-XT templates |
| GET | `/health` | Per-backend connectivity status |

## Backend configuration

Backends are declared in a JSON file (set `BACKENDS_CONFIG` env var). Without a config file, the adapter falls back to CREDEBL + Inji Verify defaults from legacy env vars.

```json
{
  "backends": [
    {
      "name": "inji-verify",
      "url": "http://inji-verify-service:8080",
      "verifyPath": "/v1/verify/vc-verification",
      "healthPath": "/v1/verify/actuator/health",
      "contentType": "application/vc+ld+json",
      "didMethods": ["did:web", "did:key", "did:jwk"],
      "successField": "verificationStatus",
      "successValue": "SUCCESS"
    },
    {
      "name": "waltid-verifier",
      "url": "http://waltid:7003",
      "verifyPath": "/openid4vc/verify",
      "healthPath": "/health",
      "didMethods": ["did:jwk", "did:web", "did:key"],
      "wrapField": "vp_token",
      "successField": "verified"
    }
  ]
}
```

Each entry declares its own auth (`tokenPath`, `apiKey`), request format (`wrapField`, `wrapArray`, `contentType`), response parsing (`successField`, `successValue`), and optional DID resolution (`resolvePath`, `resolveDocField`). Backends are selected in registration order.

## Running

```bash
# Local
go run .

# With backends config
BACKENDS_CONFIG=./backends.json go run .

# Docker
docker compose -f docker-compose.test.yml up --build
./test/smoke.sh
```

The test compose starts the adapter with `mosipid/inji-verify-service:0.16.0` and `waltid/verifier-api:0.18.2`. CREDEBL requires its full multi-service stack and connects via `host.docker.internal:8004` when running separately.

## Testing issuance → verification

The `test/issue-and-verify` tool generates an Ed25519 keypair, derives a `did:key`, signs a credential with URDNA2015, and verifies it through all three paths:

```bash
cd test/issue-and-verify && go run .
```

Output:

```txt
Direct Inji:     SUCCESS
Adapter→Inji:    SUCCESS (backend: inji-verify)
Adapter offline:  SUCCESS (level: CRYPTOGRAPHIC)
```

Credentials from credissuer.com (Ed25519Signature2020) and Inji Certify (RsaSignature2018) verify through the adapter. Walt.id's `issuer-api:0.18.2` issues `jwt_vc_json` format natively; for `ldp_vc` credentials, sign with json-gold using the walt.id-onboarded keypair.

## Why Inji Verify rejects some cross-platform credentials and how the adapter handles it

### Content-Type

Inji Verify's `/vc-verification` endpoint passes `@RequestBody String vc` directly to the MOSIP `vcverifier-jar`. When the body is `{"verifiableCredentials": [cred]}` with `Content-Type: application/json`, the library receives the wrapper object as the credential string and fails to parse it. The fix: send the raw credential as the body with `Content-Type: application/vc+ld+json`. The adapter's Inji backend preset does this automatically.

### Unknown types without @context

Inji uses Titanium JSON-LD for context expansion. Custom credential types (e.g. `UniversityDegree`) without an `@context` definition cause `INVALID_LOCAL_CONTEXT`. Adding `{"@vocab": "https://example.org/vocab#"}` to the `@context` array gives unknown terms a fallback IRI.

### Canonicalization output across implementations

All three URDNA2015 implementations produce **identical N-Quads** for the same input document:

| Implementation | Language | Used by |
| --- | --- | --- |
| json-gold | Go | This adapter (signing + offline verification) |
| Titanium JSON-LD + rdf-urdna | Java | Inji Verify (online verification) |
| @digitalbazaar/jsonld (WASM via Javy/wazero) | JS in WASM | archived |

The divergence that causes verification failures is not in the URDNA2015 algorithm. It is in **what gets canonicalized** (Content-Type causing the wrong string to be parsed) and **what terms are expandable** (missing `@vocab` for custom types). When these are handled correctly, json-gold-signed credentials verify in Inji Verify without modification.

### SD-JWT

This adapter addresses JSON-LD Data Integrity proofs. SD-JWT credentials use JWS signatures over JCS-serialized payloads and require no JSON-LD processing — that is a separate workstream.

## References

- [W3C RDF Dataset Canonicalization](https://www.w3.org/TR/rdf-canon/)
- [W3C Verifiable Credentials Data Integrity](https://www.w3.org/TR/vc-data-integrity/)
- [Node.js Adapter (original but tightly coupled to CREDBL)](https://github.com/adammwaniki/credebl-testa/tree/main/install/docker-deployment/patches/polygon-did-fix/adapter)
