/**
 * Cached JSON-LD Contexts for Offline Verification
 *
 * This file contains pre-cached JSON-LD contexts needed for offline
 * credential verification. The contexts are required for JSON-LD
 * canonicalization (URDNA2015) during signature verification.
 *
 * To add support for new credential types, add their @context URLs
 * and content to BUILTIN_CONTEXTS.
 */

const CONTEXTS_CACHE_KEY = 'inji-verify-jsonld-contexts';

/**
 * Built-in contexts that are always available offline
 * These are embedded in the bundle and don't require network access
 */
export const BUILTIN_CONTEXTS: Record<string, object> = {
  // W3C Verifiable Credentials v1 Context
  "https://www.w3.org/2018/credentials/v1": {
    "@context": {
      "@version": 1.1,
      "@protected": true,
      "id": "@id",
      "type": "@type",
      "VerifiableCredential": {
        "@id": "https://www.w3.org/2018/credentials#VerifiableCredential",
        "@context": {
          "@version": 1.1,
          "@protected": true,
          "id": "@id",
          "type": "@type",
          "cred": "https://www.w3.org/2018/credentials#",
          "sec": "https://w3id.org/security#",
          "xsd": "http://www.w3.org/2001/XMLSchema#",
          "credentialSchema": {
            "@id": "cred:credentialSchema",
            "@type": "@id",
            "@context": {
              "@version": 1.1,
              "@protected": true,
              "id": "@id",
              "type": "@type"
            }
          },
          "credentialStatus": {"@id": "cred:credentialStatus", "@type": "@id"},
          "credentialSubject": {"@id": "cred:credentialSubject", "@type": "@id"},
          "evidence": {"@id": "cred:evidence", "@type": "@id"},
          "expirationDate": {"@id": "cred:expirationDate", "@type": "xsd:dateTime"},
          "holder": {"@id": "cred:holder", "@type": "@id"},
          "issued": {"@id": "cred:issued", "@type": "xsd:dateTime"},
          "issuer": {"@id": "cred:issuer", "@type": "@id"},
          "issuanceDate": {"@id": "cred:issuanceDate", "@type": "xsd:dateTime"},
          "proof": {"@id": "sec:proof", "@type": "@id", "@container": "@graph"},
          "refreshService": {"@id": "cred:refreshService", "@type": "@id"},
          "termsOfUse": {"@id": "cred:termsOfUse", "@type": "@id"},
          "validFrom": {"@id": "cred:validFrom", "@type": "xsd:dateTime"},
          "validUntil": {"@id": "cred:validUntil", "@type": "xsd:dateTime"}
        }
      },
      "VerifiablePresentation": {
        "@id": "https://www.w3.org/2018/credentials#VerifiablePresentation",
        "@context": {
          "@version": 1.1,
          "@protected": true,
          "id": "@id",
          "type": "@type",
          "cred": "https://www.w3.org/2018/credentials#",
          "sec": "https://w3id.org/security#",
          "holder": {"@id": "cred:holder", "@type": "@id"},
          "proof": {"@id": "sec:proof", "@type": "@id", "@container": "@graph"},
          "verifiableCredential": {"@id": "cred:verifiableCredential", "@type": "@id", "@container": "@graph"}
        }
      },
      "EcdsaSecp256k1Signature2019": {
        "@id": "https://w3id.org/security#EcdsaSecp256k1Signature2019",
        "@context": {
          "@version": 1.1,
          "@protected": true,
          "id": "@id",
          "type": "@type",
          "sec": "https://w3id.org/security#",
          "xsd": "http://www.w3.org/2001/XMLSchema#",
          "challenge": "sec:challenge",
          "created": {"@id": "http://purl.org/dc/terms/created", "@type": "xsd:dateTime"},
          "domain": "sec:domain",
          "expires": {"@id": "sec:expiration", "@type": "xsd:dateTime"},
          "jws": "sec:jws",
          "nonce": "sec:nonce",
          "proofPurpose": {
            "@id": "sec:proofPurpose",
            "@type": "@vocab",
            "@context": {
              "@version": 1.1,
              "@protected": true,
              "id": "@id",
              "type": "@type",
              "sec": "https://w3id.org/security#",
              "assertionMethod": {"@id": "sec:assertionMethod", "@type": "@id", "@container": "@set"},
              "authentication": {"@id": "sec:authenticationMethod", "@type": "@id", "@container": "@set"}
            }
          },
          "proofValue": "sec:proofValue",
          "verificationMethod": {"@id": "sec:verificationMethod", "@type": "@id"}
        }
      },
      "Ed25519Signature2020": {
        "@id": "https://w3id.org/security#Ed25519Signature2020",
        "@context": {
          "@version": 1.1,
          "@protected": true,
          "id": "@id",
          "type": "@type",
          "sec": "https://w3id.org/security#",
          "xsd": "http://www.w3.org/2001/XMLSchema#",
          "challenge": "sec:challenge",
          "created": {"@id": "http://purl.org/dc/terms/created", "@type": "xsd:dateTime"},
          "domain": "sec:domain",
          "expires": {"@id": "sec:expiration", "@type": "xsd:dateTime"},
          "nonce": "sec:nonce",
          "proofPurpose": {
            "@id": "sec:proofPurpose",
            "@type": "@vocab",
            "@context": {
              "@version": 1.1,
              "@protected": true,
              "id": "@id",
              "type": "@type",
              "sec": "https://w3id.org/security#",
              "assertionMethod": {"@id": "sec:assertionMethod", "@type": "@id", "@container": "@set"},
              "authentication": {"@id": "sec:authenticationMethod", "@type": "@id", "@container": "@set"}
            }
          },
          "proofValue": "sec:proofValue",
          "verificationMethod": {"@id": "sec:verificationMethod", "@type": "@id"}
        }
      }
    }
  },

  // W3C Security v1 Context
  "https://w3id.org/security/v1": {
    "@context": {
      "id": "@id",
      "type": "@type",
      "dc": "http://purl.org/dc/terms/",
      "sec": "https://w3id.org/security#",
      "xsd": "http://www.w3.org/2001/XMLSchema#",
      "EcdsaKoblitzSignature2016": "sec:EcdsaKoblitzSignature2016",
      "Ed25519Signature2018": "sec:Ed25519Signature2018",
      "EncryptedMessage": "sec:EncryptedMessage",
      "GraphSignature2012": "sec:GraphSignature2012",
      "LinkedDataSignature2015": "sec:LinkedDataSignature2015",
      "LinkedDataSignature2016": "sec:LinkedDataSignature2016",
      "CryptographicKey": "sec:Key",
      "authenticationTag": "sec:authenticationTag",
      "canonicalizationAlgorithm": "sec:canonicalizationAlgorithm",
      "cipherAlgorithm": "sec:cipherAlgorithm",
      "cipherData": "sec:cipherData",
      "cipherKey": "sec:cipherKey",
      "created": {"@id": "dc:created", "@type": "xsd:dateTime"},
      "creator": {"@id": "dc:creator", "@type": "@id"},
      "digestAlgorithm": "sec:digestAlgorithm",
      "digestValue": "sec:digestValue",
      "domain": "sec:domain",
      "encryptionKey": "sec:encryptionKey",
      "expiration": {"@id": "sec:expiration", "@type": "xsd:dateTime"},
      "expires": {"@id": "sec:expiration", "@type": "xsd:dateTime"},
      "initializationVector": "sec:initializationVector",
      "iterationCount": "sec:iterationCount",
      "nonce": "sec:nonce",
      "normalizationAlgorithm": "sec:normalizationAlgorithm",
      "owner": {"@id": "sec:owner", "@type": "@id"},
      "password": "sec:password",
      "privateKey": {"@id": "sec:privateKey", "@type": "@id"},
      "privateKeyPem": "sec:privateKeyPem",
      "publicKey": {"@id": "sec:publicKey", "@type": "@id"},
      "publicKeyBase58": "sec:publicKeyBase58",
      "publicKeyPem": "sec:publicKeyPem",
      "publicKeyWif": "sec:publicKeyWif",
      "publicKeyService": {"@id": "sec:publicKeyService", "@type": "@id"},
      "revoked": {"@id": "sec:revoked", "@type": "xsd:dateTime"},
      "salt": "sec:salt",
      "signature": "sec:signature",
      "signatureAlgorithm": "sec:signingAlgorithm",
      "signatureValue": "sec:signatureValue"
    }
  },

  // W3C Security v2 Context (simplified)
  "https://w3id.org/security/v2": {
    "@context": {
      "@version": 1.1,
      "id": "@id",
      "type": "@type",
      "dc": "http://purl.org/dc/terms/",
      "sec": "https://w3id.org/security#",
      "xsd": "http://www.w3.org/2001/XMLSchema#",
      "Ed25519Signature2018": "sec:Ed25519Signature2018",
      "Ed25519VerificationKey2018": "sec:Ed25519VerificationKey2018",
      "EcdsaSecp256k1Signature2019": "sec:EcdsaSecp256k1Signature2019",
      "EcdsaSecp256k1VerificationKey2019": "sec:EcdsaSecp256k1VerificationKey2019",
      "assertionMethod": {"@id": "sec:assertionMethod", "@type": "@id", "@container": "@set"},
      "authentication": {"@id": "sec:authenticationMethod", "@type": "@id", "@container": "@set"},
      "controller": {"@id": "sec:controller", "@type": "@id"},
      "challenge": "sec:challenge",
      "created": {"@id": "dc:created", "@type": "xsd:dateTime"},
      "domain": "sec:domain",
      "jws": "sec:jws",
      "nonce": "sec:nonce",
      "proofPurpose": "sec:proofPurpose",
      "proofValue": "sec:proofValue",
      "publicKeyBase58": "sec:publicKeyBase58",
      "publicKeyHex": "sec:publicKeyHex",
      "publicKeyJwk": "sec:publicKeyJwk",
      "verificationMethod": {"@id": "sec:verificationMethod", "@type": "@id"}
    }
  },

  // DID v1 Context
  "https://www.w3.org/ns/did/v1": {
    "@context": {
      "@protected": true,
      "id": "@id",
      "type": "@type",
      "alsoKnownAs": {"@id": "https://www.w3.org/ns/activitystreams#alsoKnownAs", "@type": "@id"},
      "assertionMethod": {"@id": "https://w3id.org/security#assertionMethod", "@type": "@id", "@container": "@set"},
      "authentication": {"@id": "https://w3id.org/security#authenticationMethod", "@type": "@id", "@container": "@set"},
      "capabilityDelegation": {"@id": "https://w3id.org/security#capabilityDelegationMethod", "@type": "@id", "@container": "@set"},
      "capabilityInvocation": {"@id": "https://w3id.org/security#capabilityInvocationMethod", "@type": "@id", "@container": "@set"},
      "controller": {"@id": "https://w3id.org/security#controller", "@type": "@id"},
      "keyAgreement": {"@id": "https://w3id.org/security#keyAgreementMethod", "@type": "@id", "@container": "@set"},
      "service": {"@id": "https://www.w3.org/ns/did#service", "@type": "@id", "@context": {
        "@protected": true,
        "id": "@id",
        "type": "@type",
        "serviceEndpoint": {"@id": "https://www.w3.org/ns/did#serviceEndpoint", "@type": "@id"}
      }},
      "verificationMethod": {"@id": "https://w3id.org/security#verificationMethod", "@type": "@id"}
    }
  }
};

/**
 * Context Cache - manages additional contexts in localStorage
 * Built-in contexts are always available; fetched contexts are cached
 */
export const ContextCache = {
  /**
   * Get a context by URL
   * First checks built-in contexts, then localStorage cache
   */
  get(url: string): object | null {
    // Check built-in contexts first
    if (BUILTIN_CONTEXTS[url]) {
      return BUILTIN_CONTEXTS[url];
    }

    // Check localStorage cache
    try {
      const cached = localStorage.getItem(CONTEXTS_CACHE_KEY);
      if (cached) {
        const contexts = JSON.parse(cached);
        return contexts[url] || null;
      }
    } catch (e) {
      console.error('[ContextCache] Failed to read cache:', e);
    }
    return null;
  },

  /**
   * Get all cached contexts (built-in + localStorage)
   */
  getAll(): Record<string, object> {
    const all = { ...BUILTIN_CONTEXTS };

    try {
      const cached = localStorage.getItem(CONTEXTS_CACHE_KEY);
      if (cached) {
        const contexts = JSON.parse(cached);
        Object.assign(all, contexts);
      }
    } catch (e) {
      console.error('[ContextCache] Failed to read cache:', e);
    }

    return all;
  },

  /**
   * Cache a context (only if not built-in)
   */
  set(url: string, context: object): void {
    // Don't cache built-in contexts
    if (BUILTIN_CONTEXTS[url]) {
      return;
    }

    try {
      const cached = localStorage.getItem(CONTEXTS_CACHE_KEY);
      const contexts = cached ? JSON.parse(cached) : {};
      contexts[url] = context;
      localStorage.setItem(CONTEXTS_CACHE_KEY, JSON.stringify(contexts));
      console.log('[ContextCache] Cached context:', url);
    } catch (e) {
      console.error('[ContextCache] Failed to cache context:', e);
    }
  },

  /**
   * Fetch and cache a context from URL (online only)
   */
  async fetch(url: string): Promise<object | null> {
    // Return from cache if available
    const cached = this.get(url);
    if (cached) {
      return cached;
    }

    // Fetch from network
    try {
      const response = await fetch(url, {
        headers: { 'Accept': 'application/ld+json, application/json' }
      });
      if (!response.ok) {
        throw new Error(`Failed to fetch context: ${response.status}`);
      }
      const context = await response.json();
      this.set(url, context);
      return context;
    } catch (e) {
      console.error('[ContextCache] Failed to fetch context:', url, e);
      return null;
    }
  },

  /**
   * List all cached context URLs
   */
  listUrls(): string[] {
    const urls = Object.keys(BUILTIN_CONTEXTS);

    try {
      const cached = localStorage.getItem(CONTEXTS_CACHE_KEY);
      if (cached) {
        const contexts = JSON.parse(cached);
        urls.push(...Object.keys(contexts));
      }
    } catch (e) {
      console.error('[ContextCache] Failed to list URLs:', e);
    }

    return Array.from(new Set(urls)); // Remove duplicates
  },

  /**
   * Get count of cached contexts
   */
  count(): number {
    return this.listUrls().length;
  },

  /**
   * Clear cached contexts (not built-in)
   */
  clear(): void {
    localStorage.removeItem(CONTEXTS_CACHE_KEY);
    console.log('[ContextCache] Cache cleared');
  }
};

/**
 * Create an offline document loader for jsonld library
 * Returns cached contexts without making network requests
 */
export function createOfflineDocumentLoader() {
  return async (url: string) => {
    console.log('[DocumentLoader] Loading:', url);

    const context = ContextCache.get(url);
    if (context) {
      return {
        contextUrl: null,
        document: context,
        documentUrl: url
      };
    }

    throw new Error(`Context not cached: ${url}. Sync while online first.`);
  };
}

/**
 * Pre-cache contexts from a credential's @context array
 * Call this while online to prepare for offline verification
 */
export async function precacheContextsForCredential(credential: any): Promise<void> {
  const contexts = credential['@context'];
  if (!contexts) return;

  const urls = Array.isArray(contexts)
    ? contexts.filter((c: any) => typeof c === 'string')
    : typeof contexts === 'string' ? [contexts] : [];

  console.log('[ContextCache] Pre-caching contexts for credential:', urls);

  for (const url of urls) {
    await ContextCache.fetch(url);
  }
}

/**
 * Sync standard contexts commonly used by credentials
 * Call this while online to prepare for offline verification
 */
export async function syncStandardContexts(): Promise<void> {
  const standardUrls = [
    'https://www.w3.org/2018/credentials/v1',
    'https://w3id.org/security/v1',
    'https://w3id.org/security/v2',
    'https://www.w3.org/ns/did/v1'
  ];

  console.log('[ContextCache] Syncing standard contexts...');
  for (const url of standardUrls) {
    // These are all built-in, so this just verifies they're available
    const context = ContextCache.get(url);
    if (context) {
      console.log('[ContextCache] ✓', url);
    } else {
      console.log('[ContextCache] ✗', url, '(will try to fetch)');
      await ContextCache.fetch(url);
    }
  }
}
