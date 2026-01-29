# Full Offline Cryptographic Verification Plan

**Created:** 2026-01-29
**Status:** In Progress

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     TRUE OFFLINE VERIFICATION                           │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────── ONLINE SYNC PHASE ───────────────┐                   │
│  │                                                  │                   │
│  │  ┌──────────┐      ┌──────────────┐             │                   │
│  │  │ Adapter  │─────▶│ Resolve DIDs │             │                   │
│  │  │ (Node.js)│      │ Fetch Contexts│             │                   │
│  │  └──────────┘      │ Load Templates│             │                   │
│  │                    └───────┬───────┘             │                   │
│  │                            │                     │                   │
│  │                            ▼                     │                   │
│  │                    ┌───────────────┐             │                   │
│  │                    │  POST /sync   │             │                   │
│  │                    │  response     │             │                   │
│  │                    └───────┬───────┘             │                   │
│  │                            │                     │                   │
│  └────────────────────────────┼─────────────────────┘                   │
│                               │                                         │
│                               ▼                                         │
│  ┌─────────────── BROWSER STORAGE ─────────────────┐                   │
│  │                                                  │                   │
│  │   localStorage / IndexedDB                       │                   │
│  │   ┌────────────────────────────────────────┐    │                   │
│  │   │ • DID Documents (full JSON)            │    │                   │
│  │   │ • Public Keys (hex + type)             │    │                   │
│  │   │ • JSON-LD Contexts (full documents)    │    │                   │
│  │   │ • JSON-XT Templates                    │    │                   │
│  │   │ • Polygon Registry Data                │    │                   │
│  │   └────────────────────────────────────────┘    │                   │
│  │                                                  │                   │
│  └──────────────────────┬───────────────────────────┘                   │
│                         │                                               │
│                         ▼                                               │
│  ┌─────────────── OFFLINE VERIFY PHASE ────────────┐                   │
│  │                                                  │                   │
│  │   SDK (100% Browser-side)                        │                   │
│  │   ┌────────────────────────────────────────┐    │                   │
│  │   │ Bundled Libraries:                     │    │                   │
│  │   │ • @noble/secp256k1 (~50KB)            │    │                   │
│  │   │ • @noble/hashes (~20KB)               │    │                   │
│  │   │ • jsonld (~150KB browser build)       │    │                   │
│  │   │ • jsonxt (~10KB)                      │    │                   │
│  │   │ • @digitalbazaar/ed25519-* (~30KB)    │    │                   │
│  │   └────────────────────────────────────────┘    │                   │
│  │                                                  │                   │
│  │   NO NETWORK CALLS - Everything from cache       │                   │
│  │                                                  │                   │
│  └──────────────────────────────────────────────────┘                   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Key Insight: Two Separate Concerns

| Concern | Where | Why |
|---------|-------|-----|
| **Sync** (resolve DIDs, fetch contexts) | Adapter (Node.js) | No CORS, direct RPC access, no browser limitations |
| **Verify** (crypto, canonicalization) | SDK (Browser) | Must work with zero network |

---

## Browser Storage Schema

```javascript
// localStorage keys
const STORAGE_KEYS = {
    DID_DOCUMENTS: 'inji-offline-did-docs',      // { [did]: { document, resolvedAt } }
    PUBLIC_KEYS: 'inji-offline-public-keys',      // { [did]: { keyHex, keyType, keyId } }
    JSONLD_CONTEXTS: 'inji-offline-contexts',     // { [url]: documentJson }
    JSONXT_TEMPLATES: 'inji-offline-templates',   // { [templateId]: template }
    SYNC_METADATA: 'inji-offline-sync-meta'       // { lastSync, version }
};

// Estimated sizes:
// - 1 DID document: ~2KB
// - 1 JSON-LD context: ~5-50KB
// - 1 JSON-XT template: ~2KB
// - localStorage limit: ~5-10MB
// - IndexedDB limit: ~50MB+ (use for contexts)
```

---

## SDK Bundle Strategy

```javascript
// webpack.config.js
module.exports = {
    resolve: {
        fallback: {
            // These ARE needed for jsonld in browser
            "crypto": require.resolve("crypto-browserify"),
            "stream": require.resolve("stream-browserify"),
            "buffer": require.resolve("buffer/"),
            "util": require.resolve("util/"),
            // These are NOT needed
            "fs": false,
            "path": false,
            "http": false,
            "https": false,
            "url": false
        }
    },
    plugins: [
        new webpack.ProvidePlugin({
            Buffer: ['buffer', 'Buffer'],
            process: 'process/browser'
        })
    ]
};
```

---

## Component 1: Adapter Sync Endpoints

```javascript
// POST /sync/did
// Resolve and return full DID data for browser caching
Request:  { "did": "did:polygon:0x..." }
Response: {
    "did": "did:polygon:0x...",
    "didDocument": { ... },           // Full DID document
    "publicKey": {
        "keyId": "did:polygon:0x...#key-1",
        "keyType": "secp256k1",
        "publicKeyHex": "04a1b2c3..."
    },
    "resolvedAt": 1706500000000
}

// POST /sync/contexts
// Fetch and return JSON-LD contexts
Request:  { "urls": ["https://www.w3.org/2018/credentials/v1"] }
Response: {
    "contexts": {
        "https://www.w3.org/2018/credentials/v1": { "@context": { ... } }
    }
}

// GET /sync/templates
// Return JSON-XT templates
Response: {
    "educ:1": { "columns": [...], "template": {...} },
    "empl:1": { "columns": [...], "template": {...} }
}

// POST /sync/all
// Bulk sync - everything needed for offline
Request:  {
    "dids": ["did:polygon:0x...", "did:web:..."],
    "contexts": ["https://www.w3.org/2018/credentials/v1", ...],
    "includeTemplates": true
}
Response: {
    "dids": { ... },
    "contexts": { ... },
    "templates": { ... },
    "syncedAt": 1706500000000
}
```

---

## Component 2: SDK Cache Manager (Browser)

```typescript
// sdk/cache/OfflineCache.ts

export class OfflineCache {
    // DID Documents & Keys
    static setIssuer(did: string, didDocument: object, publicKey: object): void;
    static getIssuer(did: string): CachedIssuer | null;
    static listIssuers(): CachedIssuer[];
    static deleteIssuer(did: string): void;

    // JSON-LD Contexts (use IndexedDB for large contexts)
    static setContext(url: string, document: object): Promise<void>;
    static getContext(url: string): Promise<object | null>;
    static listContextUrls(): string[];

    // JSON-XT Templates
    static setTemplates(templates: object): void;
    static getTemplates(): object | null;

    // Sync status
    static getLastSync(): number | null;
    static setLastSync(timestamp: number): void;

    // Storage management
    static getStorageSize(): number;
    static clearAll(): void;

    // Create document loader for jsonld
    static createDocumentLoader(): (url: string) => Promise<object>;
}
```

---

## Component 3: SDK Crypto Verifier (Browser)

```typescript
// sdk/crypto/verifier.ts
import * as secp256k1 from '@noble/secp256k1';
import { sha256 } from '@noble/hashes/sha256';
import jsonld from 'jsonld';

export async function verifyCredentialOffline(credential: object): Promise<VerificationResult> {
    // 1. Get issuer DID
    const issuerDid = extractIssuerDid(credential);

    // 2. Get cached public key
    const cachedIssuer = OfflineCache.getIssuer(issuerDid);
    if (!cachedIssuer) {
        throw new Error(`Issuer not synced: ${issuerDid}. Sync while online first.`);
    }

    // 3. Create document loader from cache
    const documentLoader = OfflineCache.createDocumentLoader();

    // 4. Canonicalize credential
    const verifyData = await createVerifyData(credential, documentLoader);

    // 5. Verify signature based on key type
    if (cachedIssuer.keyType === 'secp256k1') {
        return verifySecp256k1Signature(verifyData, credential.proof, cachedIssuer.publicKeyHex);
    } else if (cachedIssuer.keyType === 'Ed25519') {
        return verifyEd25519Signature(verifyData, credential.proof, cachedIssuer.publicKeyHex);
    }

    throw new Error(`Unsupported key type: ${cachedIssuer.keyType}`);
}

async function createVerifyData(credential: object, documentLoader: Function): Promise<Uint8Array> {
    // Remove proof for canonicalization
    const { proof, ...credentialWithoutProof } = credential;

    // Canonicalize using URDNA2015
    const canonicalCredential = await jsonld.canonize(credentialWithoutProof, {
        algorithm: 'URDNA2015',
        format: 'application/n-quads',
        documentLoader
    });

    // Canonicalize proof options
    const proofOptions = {
        '@context': credential['@context'],
        type: proof.type,
        created: proof.created,
        verificationMethod: proof.verificationMethod,
        proofPurpose: proof.proofPurpose
    };
    const canonicalProof = await jsonld.canonize(proofOptions, {
        algorithm: 'URDNA2015',
        format: 'application/n-quads',
        documentLoader
    });

    // Hash and concatenate
    const credentialHash = sha256(new TextEncoder().encode(canonicalCredential));
    const proofHash = sha256(new TextEncoder().encode(canonicalProof));

    return concatBytes(proofHash, credentialHash);
}

function verifySecp256k1Signature(
    verifyData: Uint8Array,
    proof: object,
    publicKeyHex: string
): VerificationResult {
    // Extract signature from JWS
    const signature = extractSignatureFromJws(proof.jws);

    // Hash the verify data (secp256k1 signs hash, not raw data)
    const messageHash = sha256(verifyData);

    // Verify
    const publicKeyBytes = hexToBytes(publicKeyHex);
    const isValid = secp256k1.verify(signature, messageHash, publicKeyBytes);

    return { verified: isValid, method: 'secp256k1' };
}
```

---

## Component 4: SDK JSON-XT Decoder (Browser)

```typescript
// sdk/jsonxt/decoder.ts
import * as jsonxt from 'jsonxt';

export async function decodeJsonXtOffline(uri: string): Promise<object> {
    const templates = OfflineCache.getTemplates();
    if (!templates) {
        throw new Error('JSON-XT templates not synced. Sync while online first.');
    }

    // Create resolver that uses cached templates
    const resolver = async (resolverName: string) => templates;

    // Decode using jsonxt library
    const credential = await jsonxt.unpack(uri, resolver);

    return credential;
}
```

---

## Component 5: Floating Sync Button & Panel UI

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         INJI VERIFY UI                                  │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                     [QR Scanner / Upload Area]                   │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│                                                         ┌───────────┐   │
│                                                         │  ⚡ Sync  │   │
│                                                         │   Button  │   │
│                                                         └─────┬─────┘   │
│                                                               │         │
│  Opens Drawer Panel ◄─────────────────────────────────────────┘         │
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                    OFFLINE SYNC PANEL                             │  │
│  │  ┌─────────────────────────────────────────────────────────────┐  │  │
│  │  │ Status: ● Online    Last Sync: 2 hours ago                  │  │  │
│  │  └─────────────────────────────────────────────────────────────┘  │  │
│  │                                                                    │  │
│  │  CACHED ISSUERS (3)                                   [Sync All]  │  │
│  │  ┌─────────────────────────────────────────────────────────────┐  │  │
│  │  │ did:polygon:0xD3A2...9Fd                                    │  │  │
│  │  │ 🔑 secp256k1  │  📅 Jan 28, 2026  │  [🔄] [🗑️]              │  │  │
│  │  └─────────────────────────────────────────────────────────────┘  │  │
│  │  ┌─────────────────────────────────────────────────────────────┐  │  │
│  │  │ did:web:mosip.github.io:inji-config:collab:tan              │  │  │
│  │  │ 🔑 Ed25519    │  📅 Jan 28, 2026  │  [🔄] [🗑️]              │  │  │
│  │  └─────────────────────────────────────────────────────────────┘  │  │
│  │                                                                    │  │
│  │  ADD NEW ISSUER                                                   │  │
│  │  ┌─────────────────────────────────────────┐ ┌────────┐          │  │
│  │  │ did:polygon:0x...                       │ │ + Add  │          │  │
│  │  └─────────────────────────────────────────┘ └────────┘          │  │
│  │                                                                    │  │
│  │  JSON-LD CONTEXTS (6)                                 [Sync All]  │  │
│  │   ✓ credentials/v1  ✓ security/v1  ✓ security/v2                 │  │
│  │   ✓ secp256k1-2019  ✓ ed25519-2020  ✓ did/v1                     │  │
│  │                                                                    │  │
│  │  JSON-XT TEMPLATES (2)                                [Sync All]  │  │
│  │   ✓ educ:1 (Education)   ✓ empl:1 (Employment)                   │  │
│  │                                                                    │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌────────────────────────┐  │  │
│  │  │ 🔄 Sync All  │  │ 🗑️ Clear All │  │ Storage: 245KB / 5MB  │  │  │
│  │  └──────────────┘  └──────────────┘  └────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### UI Component Structure

```
verify-ui/src/components/
├── OfflineSync/
│   ├── OfflineSyncButton.tsx      # Floating button (⚡)
│   ├── OfflineSyncPanel.tsx       # Main panel container
│   ├── SyncStatus.tsx             # Online/offline status + last sync
│   ├── IssuerList.tsx             # List of cached issuers
│   ├── IssuerItem.tsx             # Individual issuer row
│   ├── ContextList.tsx            # List of cached JSON-LD contexts
│   ├── TemplateList.tsx           # List of cached JSON-XT templates
│   ├── AddIssuerForm.tsx          # Input to add new issuer DID
│   ├── SyncActions.tsx            # Sync All / Clear All buttons
│   └── StorageIndicator.tsx       # Storage usage bar
```

---

## Estimated Bundle Sizes

| Library | Size (minified) | Notes |
|---------|-----------------|-------|
| @noble/secp256k1 | ~50KB | Pure JS, no WASM |
| @noble/hashes | ~20KB | SHA-256, etc. |
| jsonld | ~150KB | Browser build |
| jsonxt | ~10KB | Small library |
| crypto-browserify | ~50KB | For jsonld |
| buffer | ~20KB | For jsonld |
| **Total** | **~300KB** | Acceptable for PWA |

---

## Implementation Phases

### Phase 1: Adapter Sync Endpoints
- [ ] `POST /sync/did` - Resolve and return full DID data
- [ ] `POST /sync/contexts` - Fetch and return JSON-LD contexts
- [ ] `GET /sync/templates` - Return JSON-XT templates
- [ ] `POST /sync/all` - Bulk sync endpoint

### Phase 2: SDK Cache Layer
- [ ] `OfflineCache` class with localStorage/IndexedDB
- [ ] Issuer management (set, get, list, delete)
- [ ] Context management with IndexedDB for large files
- [ ] Template management
- [ ] Storage size calculation

### Phase 3: SDK Crypto Bundle
- [ ] Webpack config with browser polyfills
- [ ] Bundle @noble/secp256k1 and @noble/hashes
- [ ] Bundle jsonld (browser build)
- [ ] Bundle jsonxt
- [ ] Test bundle size and functionality

### Phase 4: Verification Logic
- [ ] Cached document loader for jsonld
- [ ] URDNA2015 canonicalization
- [ ] secp256k1 signature verification
- [ ] Ed25519 signature verification
- [ ] JWS extraction and parsing

### Phase 5: JSON-XT Integration
- [ ] Template-based decoding with cached templates
- [ ] URL decoding handling
- [ ] Integration with verification flow

### Phase 6: Sync UI Components
- [ ] `OfflineSyncButton` floating button
- [ ] `OfflineSyncPanel` drawer component
- [ ] Issuer list with sync/delete actions
- [ ] Context and template status display
- [ ] Add issuer form
- [ ] Storage indicator
- [ ] Online/offline status

### Phase 7: Testing & Deployment
- [ ] Test sync flow while online
- [ ] Test verification while offline (airplane mode)
- [ ] Test did:polygon credentials
- [ ] Test did:web credentials
- [ ] Test JSON-XT credentials
- [ ] Deploy to EC2

---

## Files to Create/Modify

### Adapter (Node.js)
```
adapter/
├── sync-endpoints.js          # NEW: Sync API endpoints
├── resolvers/
│   ├── did-polygon.js         # NEW: Polygon DID resolver
│   ├── did-web.js             # NEW: did:web resolver
│   └── context-fetcher.js     # NEW: JSON-LD context fetcher
└── offline-adapter.js         # MODIFY: Add sync routes
```

### SDK (Browser)
```
inji-verify-sdk/src/
├── cache/
│   ├── OfflineCache.ts        # NEW: Cache manager
│   └── IndexedDBCache.ts      # NEW: IndexedDB for large data
├── crypto/
│   ├── verifier.ts            # NEW: Crypto verification
│   ├── secp256k1.ts           # NEW: secp256k1 wrapper
│   ├── ed25519.ts             # NEW: Ed25519 wrapper
│   └── canonicalize.ts        # NEW: JSON-LD canonicalization
├── jsonxt/
│   └── decoder.ts             # NEW: JSON-XT decoder
├── utils/
│   └── offlineVerifier.ts     # MODIFY: Use new crypto
└── index.ts                   # MODIFY: Export new modules
```

### Verify UI (React)
```
verify-ui/src/components/
├── OfflineSync/
│   ├── OfflineSyncButton.tsx  # NEW
│   ├── OfflineSyncPanel.tsx   # NEW
│   └── ...                    # NEW: Other components
└── App.tsx                    # MODIFY: Add sync button
```

---

## Reference: Working Commit

The last known working state (before broken changes) was at commit:
```
89d24eea41468ee49fab4118623fe4c5726c5ec4
```

Key files from that commit to preserve:
- Basic offline verification flow
- PixelPass decoding
- Simple JSON-XT decoding (template-based)
- Trusted issuer fallback

We build ON TOP of this, not replace it.
