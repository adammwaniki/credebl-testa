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
 * Built-in contexts that are always available
 */
export const BUILTIN_CONTEXTS: Record<string, object> = {
  // W3C Credentials v1 Context
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
          "proofPurpose": {"@id": "sec:proofPurpose", "@type": "@vocab", "@context": {
            "@version": 1.1,
            "@protected": true,
            "id": "@id",
            "type": "@type",
            "sec": "https://w3id.org/security#",
            "assertionMethod": {"@id": "sec:assertionMethod", "@type": "@id", "@container": "@set"},
            "authentication": {"@id": "sec:authenticationMethod", "@type": "@id", "@container": "@set"}
          }},
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
          "proofPurpose": {"@id": "sec:proofPurpose", "@type": "@vocab", "@context": {
            "@version": 1.1,
            "@protected": true,
            "id": "@id",
            "type": "@type",
            "sec": "https://w3id.org/security#",
            "assertionMethod": {"@id": "sec:assertionMethod", "@type": "@id", "@container": "@set"},
            "authentication": {"@id": "sec:authenticationMethod", "@type": "@id", "@container": "@set"}
          }},
          "proofValue": "sec:proofValue",
          "verificationMethod": {"@id": "sec:verificationMethod", "@type": "@id"}
        }
      },
      "EcdsaSecp256k1VerificationKey2019": {
        "@id": "https://w3id.org/security#EcdsaSecp256k1VerificationKey2019",
        "@context": {
          "@version": 1.1,
          "@protected": true,
          "id": "@id",
          "type": "@type",
          "sec": "https://w3id.org/security#",
          "controller": {"@id": "sec:controller", "@type": "@id"},
          "publicKeyJwk": "sec:publicKeyJwk",
          "publicKeyBase58": "sec:publicKeyBase58",
          "publicKeyHex": "sec:publicKeyHex"
        }
      },
      "Ed25519VerificationKey2020": {
        "@id": "https://w3id.org/security#Ed25519VerificationKey2020",
        "@context": {
          "@version": 1.1,
          "@protected": true,
          "id": "@id",
          "type": "@type",
          "sec": "https://w3id.org/security#",
          "controller": {"@id": "sec:controller", "@type": "@id"},
          "publicKeyMultibase": "sec:publicKeyMultibase"
        }
      }
    }
  },

  // Security v1 Context
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

  // Security v2 Context
  "https://w3id.org/security/v2": {
    "@context": [{
      "@version": 1.1
    }, "https://w3id.org/security/v1", {
      "AesKeyWrappingKey2019": "sec:AesKeyWrappingKey2019",
      "DeleteKeyOperation": "sec:DeleteKeyOperation",
      "DeriveSecretOperation": "sec:DeriveSecretOperation",
      "Ed25519Signature2018": "sec:Ed25519Signature2018",
      "Ed25519VerificationKey2018": "sec:Ed25519VerificationKey2018",
      "EquihashProof2018": "sec:EquihashProof2018",
      "ExportKeyOperation": "sec:ExportKeyOperation",
      "GenerateKeyOperation": "sec:GenerateKeyOperation",
      "KmsOperation": "sec:KmsOperation",
      "RevokeKeyOperation": "sec:RevokeKeyOperation",
      "RsaSignature2018": "sec:RsaSignature2018",
      "RsaVerificationKey2018": "sec:RsaVerificationKey2018",
      "Sha256HmacKey2019": "sec:Sha256HmacKey2019",
      "SignOperation": "sec:SignOperation",
      "UnwrapKeyOperation": "sec:UnwrapKeyOperation",
      "VerifyOperation": "sec:VerifyOperation",
      "WrapKeyOperation": "sec:WrapKeyOperation",
      "X25519KeyAgreementKey2019": "sec:X25519KeyAgreementKey2019",
      "allowedAction": "sec:allowedAction",
      "assertionMethod": {"@id": "sec:assertionMethod", "@type": "@id", "@container": "@set"},
      "authentication": {"@id": "sec:authenticationMethod", "@type": "@id", "@container": "@set"},
      "capability": {"@id": "sec:capability", "@type": "@id"},
      "capabilityAction": "sec:capabilityAction",
      "capabilityChain": {"@id": "sec:capabilityChain", "@type": "@id", "@container": "@list"},
      "capabilityDelegation": {"@id": "sec:capabilityDelegationMethod", "@type": "@id", "@container": "@set"},
      "capabilityInvocation": {"@id": "sec:capabilityInvocationMethod", "@type": "@id", "@container": "@set"},
      "caveat": {"@id": "sec:caveat", "@type": "@id", "@container": "@set"},
      "challenge": "sec:challenge",
      "ciphertext": "sec:ciphertext",
      "controller": {"@id": "sec:controller", "@type": "@id"},
      "delegator": {"@id": "sec:delegator", "@type": "@id"},
      "equihashParameterK": {"@id": "sec:equihashParameterK", "@type": "xsd:integer"},
      "equihashParameterN": {"@id": "sec:equihashParameterN", "@type": "xsd:integer"},
      "invocationTarget": {"@id": "sec:invocationTarget", "@type": "@id"},
      "invoker": {"@id": "sec:invoker", "@type": "@id"},
      "jws": "sec:jws",
      "keyAgreement": {"@id": "sec:keyAgreementMethod", "@type": "@id", "@container": "@set"},
      "kmsModule": {"@id": "sec:kmsModule"},
      "parentCapability": {"@id": "sec:parentCapability", "@type": "@id"},
      "plaintext": "sec:plaintext",
      "proof": {"@id": "sec:proof", "@type": "@id", "@container": "@graph"},
      "proofPurpose": {"@id": "sec:proofPurpose", "@type": "@vocab"},
      "proofValue": "sec:proofValue",
      "referenceId": "sec:referenceId",
      "unwrappedKey": "sec:unwrappedKey",
      "verificationMethod": {"@id": "sec:verificationMethod", "@type": "@id"},
      "verifyData": "sec:verifyData",
      "wrappedKey": "sec:wrappedKey"
    }]
  },

  // secp256k1 2019 Context
  "https://w3id.org/security/suites/secp256k1-2019/v1": {
    "@context": {
      "id": "@id",
      "type": "@type",
      "EcdsaSecp256k1Signature2019": {
        "@id": "https://w3id.org/security#EcdsaSecp256k1Signature2019",
        "@context": {
          "@version": 1.1,
          "@protected": true,
          "id": "@id",
          "type": "@type",
          "challenge": "https://w3id.org/security#challenge",
          "created": {"@id": "http://purl.org/dc/terms/created", "@type": "http://www.w3.org/2001/XMLSchema#dateTime"},
          "domain": "https://w3id.org/security#domain",
          "expires": {"@id": "https://w3id.org/security#expiration", "@type": "http://www.w3.org/2001/XMLSchema#dateTime"},
          "jws": "https://w3id.org/security#jws",
          "nonce": "https://w3id.org/security#nonce",
          "proofPurpose": {"@id": "https://w3id.org/security#proofPurpose", "@type": "@vocab"},
          "proofValue": "https://w3id.org/security#proofValue",
          "verificationMethod": {"@id": "https://w3id.org/security#verificationMethod", "@type": "@id"}
        }
      },
      "EcdsaSecp256k1VerificationKey2019": {
        "@id": "https://w3id.org/security#EcdsaSecp256k1VerificationKey2019",
        "@context": {
          "@version": 1.1,
          "@protected": true,
          "id": "@id",
          "type": "@type",
          "controller": {"@id": "https://w3id.org/security#controller", "@type": "@id"},
          "publicKeyJwk": "https://w3id.org/security#publicKeyJwk",
          "publicKeyBase58": "https://w3id.org/security#publicKeyBase58",
          "publicKeyHex": "https://w3id.org/security#publicKeyHex"
        }
      }
    }
  },

  // Ed25519 2020 Context
  "https://w3id.org/security/suites/ed25519-2020/v1": {
    "@context": {
      "id": "@id",
      "type": "@type",
      "@protected": true,
      "Ed25519Signature2020": {
        "@id": "https://w3id.org/security#Ed25519Signature2020",
        "@context": {
          "@protected": true,
          "id": "@id",
          "type": "@type",
          "challenge": "https://w3id.org/security#challenge",
          "created": {"@id": "http://purl.org/dc/terms/created", "@type": "http://www.w3.org/2001/XMLSchema#dateTime"},
          "domain": "https://w3id.org/security#domain",
          "nonce": "https://w3id.org/security#nonce",
          "proofPurpose": {"@id": "https://w3id.org/security#proofPurpose", "@type": "@vocab"},
          "proofValue": "https://w3id.org/security#proofValue",
          "verificationMethod": {"@id": "https://w3id.org/security#verificationMethod", "@type": "@id"}
        }
      },
      "Ed25519VerificationKey2020": {
        "@id": "https://w3id.org/security#Ed25519VerificationKey2020",
        "@context": {
          "@protected": true,
          "id": "@id",
          "type": "@type",
          "controller": {"@id": "https://w3id.org/security#controller", "@type": "@id"},
          "publicKeyMultibase": "https://w3id.org/security#publicKeyMultibase"
        }
      }
    }
  },

  // Schema.org context (commonly used in credentials)
  "https://schema.org": {
    "@context": {
      "@vocab": "https://schema.org/",
      "name": "https://schema.org/name",
      "description": "https://schema.org/description",
      "identifier": "https://schema.org/identifier",
      "image": {"@id": "https://schema.org/image", "@type": "@id"},
      "url": {"@id": "https://schema.org/url", "@type": "@id"}
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
 * Context Cache - stores additional contexts in localStorage
 */
export const ContextCache = {
  getAll(): Record<string, object> {
    try {
      const data = localStorage.getItem(CONTEXTS_CACHE_KEY);
      const cached = data ? JSON.parse(data) : {};
      // Merge with built-in contexts
      return { ...BUILTIN_CONTEXTS, ...cached };
    } catch (e) {
      console.error('[ContextCache] Failed to read cache:', e);
      return { ...BUILTIN_CONTEXTS };
    }
  },

  get(url: string): object | null {
    const contexts = this.getAll();
    return contexts[url] || null;
  },

  set(url: string, context: object): void {
    try {
      const data = localStorage.getItem(CONTEXTS_CACHE_KEY);
      const cached = data ? JSON.parse(data) : {};
      cached[url] = context;
      localStorage.setItem(CONTEXTS_CACHE_KEY, JSON.stringify(cached));
      console.log('[ContextCache] Cached context:', url);
    } catch (e) {
      console.error('[ContextCache] Failed to save context:', e);
    }
  },

  clear(): void {
    localStorage.removeItem(CONTEXTS_CACHE_KEY);
    console.log('[ContextCache] Cache cleared');
  },

  /**
   * Pre-fetch and cache a context from URL (while online)
   */
  async fetch(url: string): Promise<object | null> {
    // Check if already cached
    const existing = this.get(url);
    if (existing) return existing;

    // Check if it's a built-in
    if (BUILTIN_CONTEXTS[url]) return BUILTIN_CONTEXTS[url];

    try {
      const response = await fetch(url, {
        headers: { 'Accept': 'application/ld+json, application/json' }
      });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const context = await response.json();
      this.set(url, context);
      return context;
    } catch (e) {
      console.error('[ContextCache] Failed to fetch context:', url, e);
      return null;
    }
  }
};

/**
 * Create an offline document loader for jsonld library
 * This loader uses cached contexts instead of fetching from URLs
 */
export function createOfflineDocumentLoader() {
  return async (url: string): Promise<{
    contextUrl: string | null;
    document: object;
    documentUrl: string;
  }> => {
    console.log('[DocumentLoader] Loading:', url);

    // Check cache (includes built-ins)
    const cached = ContextCache.get(url);
    if (cached) {
      return {
        contextUrl: null,
        document: cached,
        documentUrl: url
      };
    }

    // Handle inline contexts (objects passed directly)
    if (typeof url === 'object') {
      return {
        contextUrl: null,
        document: url,
        documentUrl: ''
      };
    }

    throw new Error(`JSON-LD context not cached: ${url}. Sync contexts while online.`);
  };
}

/**
 * Extract all context URLs from a credential for pre-caching
 */
export function extractContextUrls(credential: object): string[] {
  const urls: string[] = [];
  const context = (credential as any)['@context'];

  if (!context) return urls;

  const processContext = (ctx: any) => {
    if (typeof ctx === 'string') {
      urls.push(ctx);
    } else if (Array.isArray(ctx)) {
      ctx.forEach(processContext);
    }
    // Objects are inline contexts, no URL to fetch
  };

  processContext(context);
  return urls;
}

/**
 * Pre-cache all contexts needed for a credential
 */
export async function precacheContextsForCredential(credential: object): Promise<void> {
  const urls = extractContextUrls(credential);
  console.log('[ContextCache] Pre-caching contexts:', urls);

  for (const url of urls) {
    await ContextCache.fetch(url);
  }
}
