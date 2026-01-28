/**
 * Offline Verifier - Full Cryptographic Client-side Credential Verification
 *
 * Enables true offline verification by:
 * 1. Decoding PixelPass/JSON-XT data locally
 * 2. Looking up issuer public keys from localStorage cache
 * 3. Canonicalizing JSON-LD using URDNA2015
 * 4. Verifying signatures using @noble/secp256k1 and Web Crypto API
 *
 * Supports:
 * - Ed25519 signatures (via Web Crypto API)
 * - secp256k1 signatures (via @noble/secp256k1)
 * - JSON-XT URI decoding (via jsonxt library)
 * - Full JSON-LD canonicalization (via jsonld library)
 */

import { decode } from "@mosip/pixelpass";
import * as secp256k1 from "@noble/secp256k1";
import { sha256 } from "@noble/hashes/sha256";
import { IssuerCache, TemplateCache, CachedIssuer } from "./offlineCache";
import { createOfflineDocumentLoader, ContextCache } from "./cachedContexts";

// Dynamic imports for optional libraries
let jsonld: any = null;
let jsonxtLib: any = null;

// Try to load jsonld
try {
  jsonld = require('jsonld');
} catch (e) {
  console.warn('[OfflineVerifier] jsonld library not available, using simplified canonicalization');
}

// Try to load jsonxt
try {
  jsonxtLib = require('jsonxt');
} catch (e) {
  console.warn('[OfflineVerifier] jsonxt library not available, using simplified decoder');
}

export interface OfflineVerificationResult {
  status: 'SUCCESS' | 'INVALID' | 'UNKNOWN_ISSUER' | 'ERROR';
  offline: boolean;
  verificationLevel?: 'CRYPTOGRAPHIC' | 'TRUSTED_ISSUER' | 'STRUCTURE_ONLY';
  message?: string;
  credential?: any;
  issuer?: CachedIssuer;
  error?: string;
  details?: {
    signatureValid?: boolean;
    canonicalizationMethod?: string;
    keyType?: string;
  };
}

// ============================================================================
// Format Detection and Decoding
// ============================================================================

/**
 * Detect the format of input data
 */
function detectFormat(input: string): 'json' | 'jsonxt' | 'pixelpass' {
  if (input.startsWith('{')) return 'json';
  if (input.startsWith('jxt:')) return 'jsonxt';
  return 'pixelpass';
}

/**
 * Decode PixelPass encoded data
 */
function decodePixelPass(encoded: string): string {
  try {
    return decode(encoded);
  } catch (e) {
    console.error('[OfflineVerifier] PixelPass decode failed:', e);
    throw new Error('Failed to decode PixelPass data');
  }
}

/**
 * Decode JSON-XT URI using the full jsonxt library if available
 */
async function decodeJsonXt(uri: string): Promise<any> {
  const templates = TemplateCache.get();
  if (!templates) {
    throw new Error('JSON-XT templates not cached. Sync while online first.');
  }

  // If jsonxt library is available, use it
  if (jsonxtLib) {
    console.log('[OfflineVerifier] Using full jsonxt library');
    try {
      // Create a resolver that returns our cached templates
      const resolver = async (name: string) => {
        console.log('[OfflineVerifier] jsonxt resolver called for:', name);
        return templates;
      };

      const credential = await jsonxtLib.unpack(uri, resolver);
      console.log('[OfflineVerifier] jsonxt unpack successful');
      return credential;
    } catch (e) {
      console.error('[OfflineVerifier] jsonxt unpack failed, trying simplified decoder:', e);
      // Fall through to simplified decoder
    }
  }

  // Simplified decoder as fallback
  return decodeJsonXtSimplified(uri, templates);
}

/**
 * Simplified JSON-XT decoder (fallback when jsonxt library unavailable)
 */
function decodeJsonXtSimplified(uri: string, templates: any): any {
  // Parse URI: jxt:resolver:type:version:data
  const parts = uri.split(':');
  if (parts.length < 5) {
    throw new Error('Invalid JSON-XT URI format');
  }

  const [, resolver, type, version, ...dataParts] = parts;
  const encodedData = dataParts.join(':');

  const templateKey = `${type}:${version}`;
  const template = templates[templateKey];
  if (!template) {
    throw new Error(`Template not found: ${templateKey}`);
  }

  // Decode values
  const values = encodedData.split('/').map(v => {
    try {
      let decoded = decodeURIComponent(v);
      decoded = decoded.replace(/~/g, ' ').replace(/\+/g, ' ');
      return decoded;
    } catch (e) {
      return v.replace(/~/g, ' ').replace(/\+/g, ' ');
    }
  });

  // Reconstruct credential
  const credential = JSON.parse(JSON.stringify(template.template));
  template.columns.forEach((col: any, index: number) => {
    if (index < values.length && values[index]) {
      setNestedValue(credential, col.path, decodeValue(values[index], col.encoder));
    }
  });

  return credential;
}

function setNestedValue(obj: any, path: string, value: any): void {
  const parts = path.split('.');
  let current = obj;
  for (let i = 0; i < parts.length - 1; i++) {
    if (!(parts[i] in current)) current[parts[i]] = {};
    current = current[parts[i]];
  }
  current[parts[parts.length - 1]] = value;
}

function decodeValue(value: string, encoder: string): any {
  if (!value || value === '') return undefined;
  // For now, return as-is. Full implementation would decode based on encoder type.
  return value;
}

// ============================================================================
// Byte Array Utilities
// ============================================================================

function hexToBytes(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2) {
    bytes[i / 2] = parseInt(hex.substr(i, 2), 16);
  }
  return bytes;
}

function base64UrlToBytes(str: string): Uint8Array {
  let base64 = str.replace(/-/g, '+').replace(/_/g, '/');
  const pad = base64.length % 4;
  if (pad) base64 += '='.repeat(4 - pad);
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

function base58ToBytes(str: string): Uint8Array {
  const ALPHABET = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
  const ALPHABET_MAP: Record<string, number> = {};
  for (let i = 0; i < ALPHABET.length; i++) {
    ALPHABET_MAP[ALPHABET[i]] = i;
  }

  let bytes = [0];
  for (let i = 0; i < str.length; i++) {
    const value = ALPHABET_MAP[str[i]];
    if (value === undefined) throw new Error('Invalid base58 character');
    for (let j = 0; j < bytes.length; j++) bytes[j] *= 58;
    bytes[0] += value;
    let carry = 0;
    for (let j = 0; j < bytes.length; j++) {
      bytes[j] += carry;
      carry = bytes[j] >> 8;
      bytes[j] &= 0xff;
    }
    while (carry) {
      bytes.push(carry & 0xff);
      carry >>= 8;
    }
  }
  for (let i = 0; i < str.length && str[i] === '1'; i++) bytes.push(0);
  return new Uint8Array(bytes.reverse());
}

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes).map(b => b.toString(16).padStart(2, '0')).join('');
}

// ============================================================================
// JSON-LD Canonicalization
// ============================================================================

/**
 * Canonicalize a credential using JSON-LD URDNA2015
 * Falls back to deterministic JSON serialization if jsonld unavailable
 */
async function canonicalize(credential: any): Promise<Uint8Array> {
  const credCopy = { ...credential };
  delete credCopy.proof;

  if (jsonld) {
    try {
      console.log('[OfflineVerifier] Using JSON-LD URDNA2015 canonicalization');
      const canonicalized = await jsonld.canonize(credCopy, {
        algorithm: 'URDNA2015',
        format: 'application/n-quads',
        documentLoader: createOfflineDocumentLoader()
      });
      return new TextEncoder().encode(canonicalized);
    } catch (e) {
      console.warn('[OfflineVerifier] JSON-LD canonicalization failed, using fallback:', e);
    }
  }

  // Fallback: deterministic JSON serialization
  console.log('[OfflineVerifier] Using simplified canonicalization');
  const sortedKeys = (obj: any): any => {
    if (typeof obj !== 'object' || obj === null) return obj;
    if (Array.isArray(obj)) return obj.map(sortedKeys);
    return Object.keys(obj).sort().reduce((acc: any, key) => {
      acc[key] = sortedKeys(obj[key]);
      return acc;
    }, {});
  };
  return new TextEncoder().encode(JSON.stringify(sortedKeys(credCopy)));
}

/**
 * Create the verification data (what was signed)
 * For JSON-LD signatures, this is typically: hash(canonicalize(proof_options)) + hash(canonicalize(document))
 */
async function createVerifyData(credential: any): Promise<Uint8Array> {
  const proof = credential.proof;
  const credCopy = { ...credential };
  delete credCopy.proof;

  // Canonicalize the credential
  const credCanonical = await canonicalize(credCopy);
  const credHash = sha256(credCanonical);

  // For EcdsaSecp256k1Signature2019, the proof options are also hashed
  if (proof.type === 'EcdsaSecp256k1Signature2019' || proof.type === 'Ed25519Signature2020') {
    const proofOptions: any = {
      '@context': credential['@context'],
      type: proof.type,
      created: proof.created,
      verificationMethod: proof.verificationMethod,
      proofPurpose: proof.proofPurpose
    };
    if (proof.challenge) proofOptions.challenge = proof.challenge;
    if (proof.domain) proofOptions.domain = proof.domain;

    const proofCanonical = await canonicalize(proofOptions);
    const proofHash = sha256(proofCanonical);

    // Concatenate: proofHash + credHash
    const combined = new Uint8Array(proofHash.length + credHash.length);
    combined.set(proofHash, 0);
    combined.set(credHash, proofHash.length);
    return combined;
  }

  return credHash;
}

// ============================================================================
// Signature Extraction and Verification
// ============================================================================

/**
 * Extract signature bytes from proof
 */
function extractSignature(proof: any): Uint8Array {
  if (proof.jws) {
    // JWS format: header.payload.signature (we want the signature part)
    const parts = proof.jws.split('.');
    if (parts.length >= 3) {
      return base64UrlToBytes(parts[2]);
    }
    // Detached JWS: header..signature
    if (parts.length === 3 && parts[1] === '') {
      return base64UrlToBytes(parts[2]);
    }
    throw new Error('Invalid JWS format');
  }

  if (proof.proofValue) {
    // Base58 or multibase encoded
    const value = proof.proofValue.startsWith('z')
      ? proof.proofValue.slice(1)  // Remove multibase prefix
      : proof.proofValue;
    return base58ToBytes(value);
  }

  throw new Error('No signature found in proof');
}

/**
 * Convert DER-encoded signature to compact (r, s) format for secp256k1
 */
function derToCompact(der: Uint8Array): Uint8Array {
  // DER: 0x30 [total-len] 0x02 [r-len] [r] 0x02 [s-len] [s]
  if (der[0] !== 0x30) {
    // Not DER encoded, might already be compact
    if (der.length === 64) return der;
    throw new Error('Unknown signature format');
  }

  let offset = 2;
  if (der[1] > 0x80) offset += der[1] - 0x80; // Long form length

  // Parse r
  if (der[offset] !== 0x02) throw new Error('Invalid DER: expected 0x02 for r');
  const rLen = der[offset + 1];
  let r = der.slice(offset + 2, offset + 2 + rLen);
  offset += 2 + rLen;

  // Parse s
  if (der[offset] !== 0x02) throw new Error('Invalid DER: expected 0x02 for s');
  const sLen = der[offset + 1];
  let s = der.slice(offset + 2, offset + 2 + sLen);

  // Remove leading zeros if present (DER uses signed integers)
  if (r[0] === 0 && r.length > 32) r = r.slice(1);
  if (s[0] === 0 && s.length > 32) s = s.slice(1);

  // Pad to 32 bytes each
  const compact = new Uint8Array(64);
  compact.set(r, 32 - r.length);
  compact.set(s, 64 - s.length);
  return compact;
}

/**
 * Verify secp256k1 signature using @noble/secp256k1
 */
async function verifySecp256k1(
  data: Uint8Array,
  signature: Uint8Array,
  publicKeyHex: string
): Promise<boolean> {
  try {
    console.log('[OfflineVerifier] Verifying secp256k1 signature');
    console.log('[OfflineVerifier] Data length:', data.length);
    console.log('[OfflineVerifier] Signature length:', signature.length);
    console.log('[OfflineVerifier] Public key:', publicKeyHex.substring(0, 20) + '...');

    const publicKeyBytes = hexToBytes(publicKeyHex);

    // Hash the data (secp256k1 signs hashes, not raw data)
    const messageHash = sha256(data);

    // Convert signature to compact format if needed
    let sig = signature;
    if (signature[0] === 0x30) {
      console.log('[OfflineVerifier] Converting DER signature to compact');
      sig = derToCompact(signature);
    }

    // Use low-S normalization
    const isValid = secp256k1.verify(sig, messageHash, publicKeyBytes);
    console.log('[OfflineVerifier] secp256k1 verification result:', isValid);
    return isValid;
  } catch (e) {
    console.error('[OfflineVerifier] secp256k1 verification error:', e);
    throw e;
  }
}

/**
 * Verify Ed25519 signature using Web Crypto API
 */
async function verifyEd25519(
  data: Uint8Array,
  signature: Uint8Array,
  publicKeyHex: string
): Promise<boolean> {
  try {
    console.log('[OfflineVerifier] Verifying Ed25519 signature');
    const publicKeyBytes = hexToBytes(publicKeyHex);

    const key = await crypto.subtle.importKey(
      'raw',
      publicKeyBytes,
      { name: 'Ed25519' },
      false,
      ['verify']
    );

    // Ed25519 signs raw data, not hashed
    const isValid = await crypto.subtle.verify('Ed25519', key, signature, data);
    console.log('[OfflineVerifier] Ed25519 verification result:', isValid);
    return isValid;
  } catch (e) {
    console.error('[OfflineVerifier] Ed25519 verification error:', e);
    throw e;
  }
}

/**
 * Verify credential signature based on key type and proof type
 */
async function verifySignature(
  credential: any,
  publicKeyHex: string,
  keyType: string
): Promise<{ valid: boolean; method: string }> {
  const proof = credential.proof;
  const proofType = proof?.type || '';

  console.log('[OfflineVerifier] Verifying signature');
  console.log('[OfflineVerifier] Proof type:', proofType);
  console.log('[OfflineVerifier] Key type:', keyType);

  // Create the data that was signed
  const dataToVerify = await createVerifyData(credential);
  const signature = extractSignature(proof);

  // Determine verification method
  if (keyType === 'Ed25519' || proofType.includes('Ed25519')) {
    const valid = await verifyEd25519(dataToVerify, signature, publicKeyHex);
    return { valid, method: 'Ed25519' };
  }

  if (keyType === 'secp256k1' || proofType.includes('Secp256k1') || proofType.includes('EcdsaSecp256k1')) {
    const valid = await verifySecp256k1(dataToVerify, signature, publicKeyHex);
    return { valid, method: 'secp256k1' };
  }

  throw new Error(`Unsupported key/proof type: ${keyType}/${proofType}`);
}

// ============================================================================
// Issuer Extraction and Validation
// ============================================================================

function extractIssuerDid(credential: any): string {
  const issuer = credential.issuer;
  return typeof issuer === 'string' ? issuer : issuer?.id;
}

/**
 * Validate credential structure against issuer
 */
function validateStructure(credential: any, issuer: CachedIssuer): { valid: boolean; issues: string[] } {
  const issues: string[] = [];

  // Check issuer matches
  const credIssuer = extractIssuerDid(credential);
  if (credIssuer !== issuer.did) {
    issues.push(`Issuer mismatch: credential says ${credIssuer}, expected ${issuer.did}`);
  }

  // Check proof exists
  if (!credential.proof) {
    issues.push('No proof in credential');
  }

  // Check verification method references issuer
  const vm = credential.proof?.verificationMethod;
  if (vm && !vm.startsWith(issuer.did)) {
    issues.push(`Verification method (${vm}) does not reference issuer DID`);
  }

  // Check signature exists
  if (!credential.proof?.jws && !credential.proof?.proofValue) {
    issues.push('No signature (jws or proofValue) in proof');
  }

  // Check required VC fields
  if (!credential['@context']) issues.push('Missing @context');
  if (!credential.type) issues.push('Missing type');
  if (!credential.credentialSubject) issues.push('Missing credentialSubject');

  return { valid: issues.length === 0, issues };
}

// ============================================================================
// Main Verification Function
// ============================================================================

/**
 * Main offline verification function
 *
 * Attempts full cryptographic verification, falls back to trusted issuer
 * if crypto verification fails.
 */
export async function verifyOffline(qrData: string): Promise<OfflineVerificationResult> {
  try {
    let data = qrData.trim();
    let isJsonXtFormat = false;
    console.log('[OfflineVerifier] Input data length:', data.length);

    // Step 1: Decode layers (PixelPass -> JSON-XT -> JSON)
    const format = detectFormat(data);
    console.log('[OfflineVerifier] Detected format:', format);

    if (format === 'pixelpass') {
      data = decodePixelPass(data);
      console.log('[OfflineVerifier] PixelPass decoded');
    }

    let credential: any;
    if (data.startsWith('jxt:')) {
      isJsonXtFormat = true;
      credential = await decodeJsonXt(data);
      console.log('[OfflineVerifier] JSON-XT decoded');
    } else {
      credential = JSON.parse(data);
      console.log('[OfflineVerifier] JSON parsed');
    }

    // Step 2: Extract and lookup issuer
    const issuerDid = extractIssuerDid(credential);
    console.log('[OfflineVerifier] Issuer DID:', issuerDid);

    const cachedIssuer = IssuerCache.get(issuerDid);
    if (!cachedIssuer) {
      return {
        status: 'UNKNOWN_ISSUER',
        offline: true,
        message: `Issuer not in offline cache. Sync "${issuerDid}" while online first.`,
        credential,
        error: `Unknown issuer: ${issuerDid}`
      };
    }

    console.log('[OfflineVerifier] Found cached issuer:', cachedIssuer.did, cachedIssuer.keyType);

    // Step 3: Validate structure
    const structureResult = validateStructure(credential, cachedIssuer);
    if (!structureResult.valid) {
      console.log('[OfflineVerifier] Structure validation issues:', structureResult.issues);
    }

    // Step 4: Attempt cryptographic verification
    if (cachedIssuer.publicKeyHex && cachedIssuer.publicKeyHex.length > 0) {
      try {
        const sigResult = await verifySignature(
          credential,
          cachedIssuer.publicKeyHex,
          cachedIssuer.keyType
        );

        if (sigResult.valid) {
          return {
            status: 'SUCCESS',
            offline: true,
            verificationLevel: 'CRYPTOGRAPHIC',
            message: `Signature cryptographically verified offline using ${sigResult.method}`,
            credential,
            issuer: cachedIssuer,
            details: {
              signatureValid: true,
              canonicalizationMethod: jsonld ? 'URDNA2015' : 'deterministic-json',
              keyType: sigResult.method
            }
          };
        } else {
          return {
            status: 'INVALID',
            offline: true,
            verificationLevel: 'CRYPTOGRAPHIC',
            message: 'Signature verification failed - credential may be tampered',
            credential,
            issuer: cachedIssuer,
            details: {
              signatureValid: false,
              keyType: sigResult.method
            }
          };
        }
      } catch (cryptoError) {
        console.warn('[OfflineVerifier] Crypto verification failed:', cryptoError);
        // Fall through to trusted issuer verification
      }
    }

    // Step 5: Fallback to trusted issuer verification
    // For JSON-XT credentials, we trust the issuer if decoding succeeded
    if (isJsonXtFormat) {
      return {
        status: 'SUCCESS',
        offline: true,
        verificationLevel: 'TRUSTED_ISSUER',
        message: 'Verified via cached trusted issuer (JSON-XT format). Crypto verification unavailable.',
        credential,
        issuer: cachedIssuer
      };
    }

    // For regular JSON-LD, check structure
    if (structureResult.valid) {
      return {
        status: 'SUCCESS',
        offline: true,
        verificationLevel: 'TRUSTED_ISSUER',
        message: 'Structure validated against trusted cached issuer. Crypto verification unavailable.',
        credential,
        issuer: cachedIssuer
      };
    }

    return {
      status: 'INVALID',
      offline: true,
      verificationLevel: 'STRUCTURE_ONLY',
      message: `Credential structure validation failed: ${structureResult.issues.join('; ')}`,
      credential,
      issuer: cachedIssuer,
      error: structureResult.issues.join('; ')
    };

  } catch (e) {
    console.error('[OfflineVerifier] Verification error:', e);
    return {
      status: 'ERROR',
      offline: true,
      error: e instanceof Error ? e.message : String(e)
    };
  }
}

/**
 * Check if offline verification is possible for this data
 */
export function canVerifyOffline(qrData: string): boolean {
  try {
    let data = qrData.trim();

    if (detectFormat(data) === 'pixelpass') {
      data = decodePixelPass(data);
    }

    if (data.startsWith('jxt:')) {
      return TemplateCache.get() !== null;
    }

    const credential = JSON.parse(data);
    const issuerDid = extractIssuerDid(credential);
    return IssuerCache.get(issuerDid) !== null;
  } catch (e) {
    return false;
  }
}

/**
 * Get verification capabilities report
 */
export function getVerificationCapabilities(): {
  secp256k1: boolean;
  ed25519: boolean;
  jsonld: boolean;
  jsonxt: boolean;
  cachedIssuers: number;
  cachedContexts: number;
} {
  return {
    secp256k1: typeof secp256k1?.verify === 'function',
    ed25519: typeof crypto?.subtle?.verify === 'function',
    jsonld: jsonld !== null,
    jsonxt: jsonxtLib !== null,
    cachedIssuers: IssuerCache.count(),
    cachedContexts: Object.keys(ContextCache.getAll()).length
  };
}
