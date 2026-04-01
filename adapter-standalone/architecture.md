# Architecture

## System context

```txt
┌─────────────────────┐
│   Verification UI   │  Inji Verify UI, mobile app, curl
│   (any client)      │
└─────────┬───────────┘
          │ POST /v1/verify/vc-verification
          │      /verify-offline
          │      /sync
          ▼
┌─────────────────────┐
│      Adapter        │  This service. Single Go binary.
│   :8085             │  Routes by DID method, verifies offline.
└──┬──────┬──────┬────┘
   │      │      │
   ▼      ▼      ▼
┌──────┐┌──────┐┌──────────────┐
│ Inji ││walt. ││   CREDEBL    │  Any backend declared
│Verify││id    ││   Agent      │  in backends.json.
│:8080 ││:7003 ││   :8004      │
└──────┘└──────┘└──────────────┘
```

The adapter sits between the verification UI and one or more verification backends. It decides whether to route online or verify locally, based on connectivity and cached issuer keys.

## Request lifecycle

```txt
Request arrives (POST /v1/verify/vc-verification)
  │
  ├─ Content-Type contains "sd-jwt"?
  │   YES → VerifySDJWT(): raw passthrough to each backend until one returns SUCCESS/INVALID
  │   (no JSON parsing, no canonicalization)
  │
  NO ↓
  │
  ├─ ParseRequestBody()
  │   ├─ PixelPass encoded? → base45 decode → zlib decompress
  │   ├─ JSON-XT URI? → template expansion → full JSON-LD credential
  │   └─ Plain JSON? → parse, check nested fields for JSON-XT URIs
  │
  ├─ ExtractCredential()
  │   Accepts: verifiableCredentials[], credential, verifiableCredential,
  │            credentialDocument, or raw body with @context
  │
  ├─ extractIssuerDID() → extractDidMethod()
  │   "did:key:z6Mk..." → "did:key"
  │
  ├─ connectivity.IsOnline(didMethod)?
  │
  │   ONLINE ↓                              OFFLINE ↓
  │   registry.Select(didMethod)            cache.Get(issuerDID)
  │     │                                     │
  │     ├─ backend found                      ├─ cached → VerifyCredentialSignature()
  │     │   → backend.Verify()                │   ├─ SUCCESS → CRYPTOGRAPHIC
  │     │   (builds request per config:       │   └─ error → validateStructure()
  │     │    wrapField, contentType,          │       ├─ valid → TRUSTED_ISSUER
  │     │    auth, successField)              │       └─ invalid → INVALID
  │     │                                     │
  │     └─ no backend                         ├─ not cached, did:key?
  │         → fall back to OFFLINE ↗          │   → ResolveDidKey() (local, no network)
  │                                           │   → cache + retry verification
  │                                           │
  │                                           └─ not cached → UNKNOWN_ISSUER
  └───────────────────────────────────────────────┘
```

## File map

```txt
adapter-standalone/
├── main.go              Entrypoint. Wires config → cache → registry → connectivity → server.
├── config.go            LoadConfig() from env vars. LoadBackends() from backends.json or env fallback.
├── backend.go           Backend interface, BackendRegistry, ConfigurableBackend (data-driven HTTP client).
│                        Preset factories: CredeblBackendConfig, InjiVerifyBackendConfig, WaltIDBackendConfig.
├── verify.go            Adapter struct. VerifyCredential (online/offline dispatch), VerifySDJWT (raw passthrough),
│                        SyncIssuer (backend resolver → direct DID resolution fallback), ParseRequestBody.
├── server.go            HTTP handlers, CORS middleware, SD-JWT content-type detection.
├── connectivity.go      Per-backend health probes. IsOnline(didMethod), IsAnyOnline(), Status().
├── cache.go             SQLite issuer cache. TTL expiry, legacy JSON migration, stats.
├── canon.go             Canonicalizer interface + NativeCanonicalizer (json-gold, URDNA2015).
├── signature.go         VerifyCredentialSignature: two-hash pattern, Ed25519, secp256k1, RSA PKCS#1v1.5.
├── did.go               DID resolution: did:key (local), did:web (HTTPS), did:polygon (eth_call).
│                        Public key extraction: multibase, hex, base58, JWK (Ed25519, secp256k1, RSA).
├── decode.go            PixelPass (Base45 + zlib per RFC 9285), JSON-XT template expansion.
├── backends.json        Default backend config: inji-verify, waltid-verifier, credebl-agent.
├── Dockerfile           Multi-stage: golang:1.24-alpine → alpine:3.21. CGO_ENABLED=0.
├── docker-compose.test.yml   Test stack: adapter + inji-verify + walt.id verifier + walt.id issuer + walt.id wallet.
└── test/
    ├── smoke.sh                    Health + connectivity + basic verification checks.
    ├── issue-and-verify/main.go    Signs credential with json-gold, verifies through all paths.
    └── waltid-verifier/config/     Minimal walt.id verifier configuration.
```

## Backend interface

```go
type Backend interface {
    Name() string
    CanVerify(didMethod string) bool
    Verify(credential map[string]any) VerificationResult      // JSON-LD credentials
    VerifyRaw(token string, contentType string) VerificationResult  // SD-JWT, raw strings
    HealthEndpoint() string
}
```

`ConfigurableBackend` implements this entirely from `BackendConfig` data — endpoint paths, auth, request wrapping, response parsing. Adding a backend is a JSON entry, not Go code.

`DIDResolverBackend` is an optional extension for backends that can resolve DID documents (used by `/sync`).

## Verification modes

### Online (LDP_VC)

The adapter selects a backend by DID method (`registry.Select`), builds a request per the backend's config (`wrapField`, `contentType`, `tokenPath`), sends it, and interprets the response (`successField`, `successValue`).

For Inji Verify: raw credential body + `Content-Type: application/vc+ld+json`. For CREDEBL Agent: `{"credential": cred}` + bearer token from `/agent/token`.

### Online (SD-JWT)

Raw token string forwarded to each backend in registration order with the original `Content-Type` preserved. First backend returning SUCCESS or INVALID wins.

### Offline (CRYPTOGRAPHIC)

```txt
credential (without proof)  ──>  URDNA2015  ──>  SHA256  ────> ┐
                                                               ├──>  Ed25519.Verify / RSA.Verify
proof options (with @context) ──>  URDNA2015  ──>  SHA256  ──> ┘
```

json-gold fetches `@context` URLs over HTTP on first use and caches them. Custom contexts (e.g. `credissuer.com/templates/...`) resolve automatically.

### Offline (TRUSTED_ISSUER)

Fallback when cryptographic verification fails (unsupported proof type, context fetch error). Checks: issuer DID matches cache, proof references issuer, required VC fields present.

## Connectivity

`ConnectivityChecker` probes each registered backend's `healthPath` at a configurable interval. `IsOnline(didMethod)` returns true if at least one backend that handles that DID method is reachable. Per-backend status is exposed at `/health`.

## Cache

SQLite via `modernc.org/sqlite` (pure Go, no CGO). Schema:

```sql
issuers (did TEXT PRIMARY KEY, did_document TEXT, public_key_hex TEXT, key_type TEXT, cached_at INTEGER)
metadata (key TEXT PRIMARY KEY, value TEXT, updated_at INTEGER)
```

`/sync` resolves a DID, extracts the public key, and stores it. Resolution tries the backend's `resolvePath` first, then falls back to direct DID method resolution (did:key local, did:web HTTPS, did:polygon eth_call).

## DID method routing (default backends.json)

| DID method | Backend | Auth | Content-Type |
| --- | --- | --- | --- |
| did:polygon, did:indy, did:sov, did:peer | credebl-agent | Bearer token via `/agent/token` | application/json |
| did:web, did:key, did:jwk | inji-verify | None | application/vc+ld+json |
| did:jwk, did:web, did:key, did:cheqd | waltid-verifier | None | application/json |

First match wins. Inji Verify is registered before walt.id, so `did:web`/`did:key`/`did:jwk` route to Inji by default.

## Credential format support

| Format | Online | Offline |
| --- | --- | --- |
| LDP_VC (Ed25519Signature2018) | Inji Verify, CREDEBL | CRYPTOGRAPHIC |
| LDP_VC (Ed25519Signature2020) | Inji Verify, CREDEBL | CRYPTOGRAPHIC |
| LDP_VC (EcdsaSecp256k1Signature2019) | CREDEBL | CRYPTOGRAPHIC |
| LDP_VC (RsaSignature2018) | Inji Verify | CRYPTOGRAPHIC (if RSA key cached) |
| SD-JWT (EdDSA, x5c in header) | Inji Verify | Not supported (passthrough only) |
| SD-JWT (EdDSA, kid/DID) | Not supported by Inji 0.16.0 | Not supported |
| JWT_VC_JSON | walt.id (OID4VP flow) | Not supported |

## Differences from the original Node.js adapter

The [original adapter](https://github.com/adammwaniki/credebl-testa/tree/main/install/docker-deployment/patches/polygon-did-fix/adapter) is a 1500-line Node.js file hardcoded to CREDEBL Agent and Inji Verify. This standalone adapter preserves the same API surface and routing logic with two intentional changes:

1. **Content-Type fix.** The original sends `application/json` with `{"verifiableCredentials": [cred]}` to Inji Verify. Inji's controller passes `@RequestBody String vc` to the verifier library — when the body is the wrapper object, parsing fails. The standalone sends the raw credential with `Content-Type: application/vc+ld+json`, matching the delegated-access-poc's approach.

2. **Removed Ed25519Signature2020 offline-preference heuristic.** The original forces offline for `did:web`/`did:key` with Ed25519Signature2020 if cached, commenting "Inji Verify can't fetch JSON-LD contexts from w3id.org". With the Content-Type fix, Inji Verify handles these credentials correctly online. The heuristic is no longer needed.

Everything else is preserved: same endpoints, same DID method routing, same offline fallback chain (crypto → trusted-issuer → unknown), same PixelPass + JSON-XT decoding, same sync with DID resolution fallback, same CORS handling.
