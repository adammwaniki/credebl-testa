# CREDEBL + Inji Verify Offline Verification PoC

## Architectural Documentation

**Version:** 1.0
**Date:** January 2026
**Authors:** CDPI Team

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Storyboard](#2-storyboard)
3. [Entity Relationship Diagram (ERD)](#3-entity-relationship-diagram-erd)
4. [Data Flow Diagram (DFD)](#4-data-flow-diagram-dfd)
5. [Adapter Service Architecture](#5-adapter-service-architecture)
6. [Endpoints Reference](#6-endpoints-reference)
7. [Deployment Architecture](#7-deployment-architecture)

---

## 1. Executive Summary

This Proof of Concept demonstrates a complete Verifiable Credentials ecosystem that supports **offline verification** for remote/disconnected environments. The system integrates:

- **CREDEBL Platform** - Open-source SSI platform for credential management
- **Credo Agent** - Aries Framework JavaScript agent with Polygon DID support
- **Inji Verify** - MOSIP's credential verification interface
- **Custom Verification Adapter** - Offline-capable verification service

### Key Innovation

The verification adapter enables credential verification in environments with limited or no internet connectivity by:

- Caching issuer DID documents and public keys
- Providing trusted issuer verification when full cryptographic verification isn't possible
- Seamlessly switching between online and offline modes

### Use Case

Remote village deployment where students need to verify education credentials without reliable internet connectivity.

---

## 2. Storyboard

### Overview

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                        CREDENTIAL LIFECYCLE                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────────────────┐  │
│   │  PHASE 1 │───▶│  PHASE 2 │───▶│  PHASE 3 │───▶│       PHASE 4        │  │
│   │  Setup   │    │  Issue   │    │   Hold   │    │       Verify         │  │
│   └──────────┘    └──────────┘    └──────────┘    └──────────────────────┘  │
│                                                     │                    │   │
│                                                     ▼                    ▼   │
│                                                  [Online]           [Offline]│
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

### Phase 1: Platform & Agent Setup

#### 1.1 Platform Administrator Onboarding

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 1.1: Platform Admin Registration                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌─────────┐         ┌─────────────┐         ┌──────────────┐              │
│   │  Admin  │────────▶│  Keycloak   │────────▶│   CREDEBL    │              │
│   │  User   │ Register│    SSO      │ Auth    │   Platform   │              │
│   └─────────┘         └─────────────┘         └──────────────┘              │
│                                                      │                      │
│                                                      ▼                      │
│                                               ┌──────────────┐              │
│                                               │  PostgreSQL  │              │
│                                               │  (user data) │              │
│                                               └──────────────┘              │
│                                                                             │
│   Actions:                                                                  │
│   • Admin registers via Keycloak                                            │
│   • Profile created in CREDEBL database                                     │
│   • Admin receives platform access                                          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### 1.2 Organization Creation

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 1.2: Organization Setup                                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌─────────┐         ┌─────────────┐         ┌──────────────┐              │
│   │  Admin  │────────▶│  CREDEBL    │────────▶│ Organization │              │
│   │         │ Create  │  API        │ Store   │   Service    │              │
│   └─────────┘         └─────────────┘         └──────────────┘              │
│                                                      │                      │
│                              ┌───────────────────────┼───────────────────┐  │
│                              ▼                       ▼                   ▼  │
│                       ┌──────────┐           ┌──────────┐         ┌───────┐ │
│                       │   Org    │           │   Org    │         │ Org   │ │
│                       │ Profile  │           │  Wallet  │         │ Role  │ │
│                       └──────────┘           └──────────┘         └───────┘ │
│                                                                             │
│   Data Created:                                                             │
│   • Organization profile (name, description, logo)                          │
│   • Organization wallet (for key management)                                │
│   • User-organization role mapping                                          │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### 1.3 Agent Provisioning

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 1.3: Dedicated Agent Provisioning                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌─────────┐         ┌─────────────┐         ┌──────────────┐              │
│   │  Admin  │────────▶│  Agent      │────────▶│    Credo     │              │
│   │         │ Request │ Provisioning│ Spin Up │  Controller  │              │
│   └─────────┘         │  Service    │         │   (Agent)    │              │
│                       └─────────────┘         └──────────────┘              │
│                              │                       │                      │
│                              ▼                       ▼                      │
│                       ┌──────────────┐       ┌──────────────┐               │
│                       │    Agent     │       │   Polygon    │               │
│                       │    Config    │       │  Blockchain  │               │
│                       │    (JSON)    │       │  (DID Reg)   │               │
│                       └──────────────┘       └──────────────┘               │
│                                                                             │
│   Agent Setup:                                                              │
│   • Generate wallet with master key                                         │
│   • Create DID e.g., did:polygon (on Amoy testnet or even mainnet)          │
│   • Register DID document on-chain                                          │
│   • Configure agent endpoints                                               │
│   • Store agent config in platform                                          │
│                                                                             │
│   DID Document (on-chain):                                                  │
│   {                                                                         │
│     "id": "did:polygon:0xD3A288e4cCeb5ADE57c5B674475d6728Af3bD9Fd",         │
│     "verificationMethod": [{                                                │
│       "id": "...#key-1",                                                    │
│       "type": "EcdsaSecp256k1VerificationKey2019",                          │
│       "publicKeyHex": "04abc123..."                                         │
│     }]                                                                      │
│   }                                                                         │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### 1.4 Schema & Credential Definition

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 1.4: Schema Creation                                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌─────────┐         ┌─────────────┐         ┌──────────────┐              │
│   │ Issuer  │────────▶│  CREDEBL    │────────▶│   Schema     │              │
│   │  Admin  │ Define  │  Platform   │ Store   │  File Server │              │
│   └─────────┘ Schema  └─────────────┘         └──────────────┘              │
│                                                                             │
│   Schema Definition:                                                        │
│   {                                                                         │
│     "name": "BeneficiaryCredential",                                        │
│     "version": "1.0",                                                       │
│     "attributes": [                                                         │
│       "fullName",                                                           │
│       "dateOfBirth",                                                        │
│       "nationalId",                                                         │
│       "beneficiaryType",                                                    │
│       "issuedOn"                                                            │
│     ]                                                                       │
│   }                                                                         │
│                                                                             │
│   W3C Credential Context:                                                   │
│   • Schema stored at public URL                                             │
│   • JSON-LD context generated                                               │
│   • Linked to organization DID                                              │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

### Phase 2: Credential Issuance

#### 2.1 Holder Registration

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 2.1: Holder/Beneficiary Registration                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌─────────┐         ┌─────────────┐         ┌──────────────┐              │
│   │ Holder  │────────▶│   Inji      │────────▶│   CREDEBL    │              │
│   │ (Person)│ Register│   Wallet    │ Create  │  Cloud Wallet│              │
│   └─────────┘         │    App      │ Wallet  │   Service    │              │
│                       └─────────────┘         └──────────────┘              │
│                                                      │                      │
│                                                      ▼                      │
│                                               ┌──────────────┐              │
│                                               │  did:jwk or  │              │
│                                               │  did:key     │              │
│                                               │  (generated) │              │
│                                               └──────────────┘              │
│                                                                             │
│   Holder Setup:                                                             │
│   • Mobile wallet generates local key pair                                  │
│   • DID created (did:jwk or did:key)                                        │
│   • Wallet ready to receive credentials                                     │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### 2.2 Credential Issuance Flow

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 2.2: Credential Issuance                                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐   │
│   │ Issuer  │───▶│ CREDEBL │───▶│  Credo  │───▶│ Polygon │───▶│ Holder  │   │
│   │  Admin  │    │   API   │    │  Agent  │    │   RPC   │    │ Wallet  │   │
│   └─────────┘    └─────────┘    └─────────┘    └─────────┘    └─────────┘   │
│                                                                             │
│   Step-by-Step:                                                             │
│                                                                             │
│   1. Issuer initiates credential offer                                      │
│      POST /api/v1/credentials/offer                                         │
│      {                                                                      │
│        "schemaId": "...",                                                   │
│        "holderDid": "did:jwk:...",                                          │
│        "attributes": { "fullName": "John Doe", ... }                        │
│      }                                                                      │
│                                                                             │
│   2. CREDEBL routes to Credo Agent                                          │
│      POST /agent/credential/issue                                           │
│                                                                             │
│   3. Agent creates W3C Verifiable Credential                                │
│      - Builds credential JSON-LD                                            │
│      - Signs with issuer's private key                                      │
│      - Proof type: EcdsaSecp256k1Signature2019                              │
│                                                                             │
│   4. Signed credential returned                                             │
│      {                                                                      │
│        "@context": [...],                                                   │
│        "type": ["VerifiableCredential", "BeneficiaryCredential"],           │
│        "issuer": "did:polygon:0xD3A288...",                                 │
│        "credentialSubject": { ... },                                        │
│        "proof": {                                                           │
│          "type": "EcdsaSecp256k1Signature2019",                             │
│          "verificationMethod": "did:polygon:...#key-1",                     │
│          "proofValue": "z..."                                               │
│        }                                                                    │
│      }                                                                      │
│                                                                             │
│   5. Credential delivered to holder wallet                                  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

### Phase 3: Credential Holding (QR Generation)

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 3: QR Code Generation & Storage                                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                         HOLDER WALLET                               │   │
│   │                                                                     │   │
│   │   ┌─────────────┐         ┌─────────────┐         ┌─────────────┐   │   │
│   │   │ Credential  │────────▶│  QR Code    │────────▶│   Display   │   │   │
│   │   │   (JSON)    │ Encode  │  Generator  │ Render  │   on App    │   │   │
│   │   └─────────────┘         └─────────────┘         └─────────────┘   │   │
│   │                                                                     │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│   QR Encoding Options:                                                      │
│                                                                             │
│   Option A: Full Credential (for small credentials)                         │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │  QR contains: CBOR format embedded credential                       │   │
│   │  Pros: Self-contained, works completely offline                     │   │
│   │  Cons: Large QR code, limited data capacity                         │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│   Option B: Reference URL (for large credentials)                           │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │  QR contains: https://holder.wallet/credentials/{id}                │   │
│   │  Pros: Small QR code, unlimited credential size                     │   │
│   │  Cons: Requires network to fetch credential                         │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│   This PoC: Uses Option A (embedded credential) for offline support         │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

### Phase 4: Credential Verification

#### 4.1 Online Verification Flow

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 4.1: Online Verification                                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐   │
│   │Verifier │───▶│  Inji   │───▶│Verif.   │───▶│ Backend │───▶│Polygon/ │   │
│   │ (Scan)  │    │ Verify  │    │Adapter  │    │ Service │    │DID Res. │   │
│   └─────────┘    │   UI    │    └─────────┘    └─────────┘    └─────────┘   │
│                  └─────────┘                                                │
│                                                                             │
│   Flow:                                                                     │
│                                                                             │
│   1. Verifier scans QR code with Inji Verify                                │
│                                                                             │
│   2. UI sends credential to adapter                                         │
│      POST /v1/verify/vc-verification                                        │
│                                                                             │
│   3. Adapter detects DID method                                             │
│      • did:polygon → Route to CREDEBL Agent                                 │
│      • did:web/key → Route to Inji Verify Service                           │
│                                                                             │
│   4. Backend verification:                                                  │
│      a. Resolve issuer DID document (from blockchain/web)                   │
│      b. Extract public key                                                  │
│      c. Verify signature cryptographically                                  │
│      d. Check credential not expired                                        │
│      e. (Optional) Check revocation status                                  │
│                                                                             │
│   5. Return verification result                                             │
│      { "verificationStatus": "SUCCESS" }                                    │
│                                                                             │
│   Verification Levels:                                                      │
│   • CRYPTOGRAPHIC: Full signature verification ✓                            │
│   • TRUSTED_ISSUER: Issuer in trusted registry                              │
│   • INVALID: Verification failed                                            │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### 4.2 Offline Verification Flow

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│ STEP 4.2: Offline Verification                                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   PREREQUISITE: Sync issuers while online                                   │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │  POST /sync { "did": "did:polygon:0x..." }                          │   │
│   │  → Fetches DID document, extracts public key, caches locally        │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│   ┌─────────┐    ┌─────────┐    ┌─────────────────────────────────────┐     │
│   │Verifier │───▶│  Inji   │───▶│       VERIFICATION ADAPTER          │     │
│   │ (Scan)  │    │ Verify  │    │  ┌─────────────────────────────────┐│     │
│   └─────────┘    │   UI    │    │  │         LOCAL CACHE             ││     │
│                  └─────────┘    │  │  ┌───────────────────────────┐  ││     │
│                                 │  │  │ did:polygon:0xD3A...      │  ││     │
│                                 │  │  │ publicKeyHex: "04abc..."  │  ││     │
│                                 │  │  │ cachedAt: 2026-01-21      │  ││     │
│                                 │  │  └───────────────────────────┘  ││     │
│                                 │  │  ┌───────────────────────────┐  ││     │
│                                 │  │  │ did:web:mosip.github...   │  ││     │
│                                 │  │  │ publicKeyHex: "e8d0e7..." │  ││     │
│                                 │  │  │ cachedAt: 2026-01-21      │  ││     │
│                                 │  │  └───────────────────────────┘  ││     │
│                                 │  └─────────────────────────────────┘│     │
│                                 └─────────────────────────────────────┘     │
│                                                                             │
│   Offline Flow:                                                             │
│                                                                             │
│   1. Verifier scans QR code (no network)                                    │
│                                                                             │
│   2. Adapter receives credential                                            │
│      POST /v1/verify/vc-verification                                        │
│                                                                             │
│   3. Adapter detects offline (connectivity check fails)                     │
│                                                                             │
│   4. Lookup issuer in local cache                                           │
│      • Found → Proceed to verification                                      │
│      • Not found → Return "UNKNOWN_ISSUER"                                  │
│                                                                             │
│   5. Validate credential structure                                          │
│      • Check issuer matches cached DID                                      │
│      • Verify proof exists and references issuer                            │
│      • Validate credential fields present                                   │
│      • Check expiration date                                                │
│                                                                             │
│   6. Return verification result                                             │
│      {                                                                      │
│        "verificationStatus": "SUCCESS",                                     │
│        "offline": true,                                                     │
│        "verificationLevel": "TRUSTED_ISSUER",                               │
│        "cachedIssuer": { "did": "...", "cachedAt": "..." }                  │
│      }                                                                      │
│                                                                             │
│   Note: Ed25519Signature2020 requires JSON-LD canonicalization              │
│   which isn't available offline, so we fall back to trusted issuer mode.    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Entity Relationship Diagram (ERD)

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                          ENTITY RELATIONSHIP DIAGRAM                        │
└─────────────────────────────────────────────────────────────────────────────┘

                                    ┌──────────────┐
                                    │    USER      │
                                    ├──────────────┤
                                    │ id           │
                                    │ email        │
                                    │ keycloakId   │
                                    │ role         │
                                    └──────┬───────┘
                                           │
                                           │ belongs_to (N:M)
                                           ▼
┌──────────────┐                  ┌──────────────┐                  ┌──────────────┐
│    AGENT     │◀─────────────────│ ORGANIZATION │─────────────────▶│   WALLET     │
├──────────────┤   has_agent (1:1)├──────────────┤   has_wallet     ├──────────────┤
│ id           │                  │ id           │      (1:1)       │ id           │
│ orgId        │                  │ name         │                  │ orgId        │
│ did          │                  │ description  │                  │ masterKey    │
│ walletId     │                  │ logo         │                  │ type         │
│ endpoints    │                  │ status       │                  └──────────────┘
│ config (JSON)│                  └──────┬───────┘
└──────────────┘                         │
       │                                 │ creates (1:N)
       │                                 ▼
       │                        ┌──────────────┐
       │                        │    SCHEMA    │
       │                        ├──────────────┤
       │                        │ id           │
       │                        │ name         │
       │                        │ version      │
       │                        │ attributes[] │
       │                        │ orgId        │
       │                        └──────┬───────┘
       │                               │
       │                               │ defines (1:N)
       │                               ▼
       │                        ┌──────────────┐
       │ issues (1:N)           │  CRED_DEF    │
       └───────────────────────▶├──────────────┤
                                │ id           │
                                │ schemaId     │
                                │ agentId      │
                                │ tag          │
                                └──────┬───────┘
                                       │
                                       │ used_by (1:N)
                                       ▼
                               ┌───────────────┐
                               │  CREDENTIAL   │
                               ├───────────────┤
                               │ id            │
                               │ credDefId     │
                               │ holderId      │
                               │ attributes    │
                               │ status        │
                               │ issuedAt      │
                               │ expiresAt     │
                               └───────┬───────┘
                                       │
                                       │ held_by (N:1)
                                       ▼
                               ┌───────────────┐
                               │    HOLDER     │
                               ├───────────────┤
                               │ id            │
                               │ did           │
                               │ walletType    │
                               └───────────────┘


┌─────────────────────────────────────────────────────────────────────────────┐
│                    VERIFICATION ADAPTER ENTITIES                            │
└─────────────────────────────────────────────────────────────────────────────┘

┌───────────────────┐              ┌───────────────────┐
│   ISSUER_CACHE    │              │  CONTEXT_CACHE    │
├───────────────────┤              ├───────────────────┤
│ did (PK)          │              │ url (PK)          │
│ didDocument       │              │ content           │
│ publicKeyHex      │              │ cachedAt          │
│ keyType           │              └───────────────────┘
│ cachedAt          │
│ expiresAt         │
└───────────────────┘


┌─────────────────────────────────────────────────────────────────────────────┐
│                         BLOCKCHAIN ENTITIES                                 │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                        POLYGON MAINNET OR AMOY TESTNET                      │
│                                                                             │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                    DID REGISTRY CONTRACT                            │   │
│   │                 0x0C76cc3DC2c12E274123e84a34eb176C3912543c          │   │
│   │                                                                     │   │
│   │   ┌─────────────────────────────────────────────────────────────┐   │   │
│   │   │ Mapping: address → DID Document (JSON string)               │   │   │
│   │   │                                                             │   │   │
│   │   │ 0xD3A288e4cCeb5ADE57c5B674475d6728Af3bD9Fd → {              │   │   │
│   │   │   "id": "did:polygon:0xD3A288...",                          │   │   │
│   │   │   "verificationMethod": [...]                               │   │   │
│   │   │ }                                                           │   │   │
│   │   └─────────────────────────────────────────────────────────────┘   │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

Transaction record

([Polygon Scan](https://polygonscan.com/tx/0xe925c1a75703e674d6f7d0fea4fc023ef8175c69e3134b494fc379cda92e26af))

### ERD Key Relationships

| Relationship | Cardinality | Description |
|--------------|-------------|-------------|
| User ↔ Organization | N:M | Users can belong to multiple organizations with different roles |
| Organization → Agent | 1:1 | Each organization has one dedicated agent |
| Organization → Wallet | 1:1 | Each organization has one wallet for key management |
| Organization → Schema | 1:N | Organizations can create multiple schemas |
| Schema → CredDef | 1:N | Each schema can have multiple credential definitions |
| Agent → Credential | 1:N | Agents issue multiple credentials |
| Credential → Holder | N:1 | Holders can have multiple credentials |

---

## 4. Data Flow Diagram (DFD)

### Level 0: Context Diagram

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                           CONTEXT DIAGRAM (DFD Level 0)                     │
└─────────────────────────────────────────────────────────────────────────────┘

                         ┌─────────────────────┐
                         │                     │
         Credentials     │      ISSUER         │     Admin Actions
        ◀────────────────│    (Organization)   │◀────────────────
                         │                     │
                         └─────────────────────┘
                                   │
                                   │ Issue Credential
                                   ▼
┌─────────────┐          ┌─────────────────────┐          ┌─────────────┐
│             │          │                     │          │             │
│   HOLDER    │─────────▶│   CREDEBL + INJI    │◀─────────│  VERIFIER   │
│  (Wallet)   │ Present  │      SYSTEM         │  Verify  │   (Scan)    │
│             │◀─────────│                     │─────────▶│             │
└─────────────┘ Response └─────────────────────┘  Result  └─────────────┘
                                   │
                                   │ DID Resolution
                                   ▼
                         ┌─────────────────────┐
                         │                     │
                         │  POLYGON BLOCKCHAIN │
                         │   (DID Registry)    │
                         │                     │
                         └─────────────────────┘
```

### Level 1: System Processes

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                        DATA FLOW DIAGRAM (DFD Level 1)                       │
└─────────────────────────────────────────────────────────────────────────────┘


    ┌──────────┐                                              ┌──────────┐
    │  ISSUER  │                                              │  HOLDER  │
    └────┬─────┘                                              └────┬─────┘
         │                                                         │
         │ [1] Create Schema                                       │
         │ [2] Issue Credential                                    │
         ▼                                                         │
    ┌─────────────────────┐                                        │
    │                     │     [3] Credential                     │
    │   1.0 CREDENTIAL    │────────────────────────────────────────▶
    │     ISSUANCE        │                                        │
    │                     │                                        │
    └─────────┬───────────┘                                        │
              │                                                    │
              │ [4] Store                                          │
              ▼                                                    │
    ┌─────────────────────┐                                        │
    │                     │                                        │
    │   D1: CREDENTIAL    │                                        │
    │       STORE         │                                        │
    │                     │                                        │
    └─────────────────────┘                                        │
                                                                   │
                                                                   │
    ┌──────────┐                                                   │
    │ VERIFIER │                                                   │
    └────┬─────┘                                                   │
         │                                                         │
         │ [5] Scan QR                    [6] Present Credential   │
         ▼                                ◀────────────────────────┘
    ┌─────────────────────┐
    │                     │
    │  2.0 CREDENTIAL     │
    │   VERIFICATION      │
    │                     │
    └─────────┬───────────┘
              │
              │ [7] Route based on DID method
              ▼
    ┌─────────────────────────────────────────────────────────────────────┐
    │                                                                     │
    │  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐  │
    │  │                 │    │                 │    │                 │  │
    │  │ 2.1 ONLINE      │    │ 2.2 OFFLINE     │    │ 2.3 CACHED      │  │
    │  │ VERIFICATION    │    │ VERIFICATION    │    │ ISSUER CHECK    │  │
    │  │                 │    │                 │    │                 │  │
    │  └────────┬────────┘    └────────┬────────┘    └────────┬────────┘  │
    │           │                      │                      │           │
    │           ▼                      ▼                      ▼           │
    │  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐  │
    │  │                 │    │                 │    │                 │  │
    │  │ D2: BLOCKCHAIN  │    │ D3: ISSUER      │    │ D3: ISSUER      │  │
    │  │ (Polygon/Web)   │    │     CACHE       │    │     CACHE       │  │
    │  │                 │    │                 │    │                 │  │
    │  └─────────────────┘    └─────────────────┘    └─────────────────┘  │
    │                                                                     │
    └─────────────────────────────────────────────────────────────────────┘
              │
              │ [8] Verification Result
              ▼
    ┌──────────┐
    │ VERIFIER │  { "verificationStatus": "SUCCESS" }
    └──────────┘
```

### Online vs Offline Data Flows

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                    ONLINE VERIFICATION DATA FLOW                             │
└─────────────────────────────────────────────────────────────────────────────┘

┌────────┐    ┌────────┐    ┌────────┐    ┌────────┐    ┌────────┐    ┌────────┐
│  Scan  │───▶│  Inji  │───▶│Adapter │───▶│ Agent/ │───▶│Polygon │───▶│ Result │
│   QR   │    │Verify  │    │        │    │  Inji  │    │  RPC   │    │SUCCESS │
│        │    │   UI   │    │        │    │Service │    │        │    │        │
└────────┘    └────────┘    └────────┘    └────────┘    └────────┘    └────────┘
                  │              │              │              │
                  │    HTTP      │    HTTP      │   JSON-RPC   │
                  │    POST      │    POST      │   eth_call   │
                  ▼              ▼              ▼              ▼
              credential    credential    credential    DID Document
                JSON          JSON          JSON         (on-chain)
                                                              │
                                                              ▼
                                                        Public Key
                                                              │
                                                              ▼
                                                    Signature Verified ✓


┌─────────────────────────────────────────────────────────────────────────────┐
│                    OFFLINE VERIFICATION DATA FLOW                           │
└─────────────────────────────────────────────────────────────────────────────┘

┌────────┐    ┌────────┐    ┌────────┐    ┌────────────────────────────────────┐
│  Scan  │───▶│  Inji  │───▶│Adapter │───▶│           LOCAL CACHE              │
│   QR   │    │Verify  │    │        │    │  ┌────────────────────────────┐    │
│        │    │   UI   │    │        │    │  │ Issuer: did:polygon:0x...  │    │
└────────┘    └────────┘    └────────┘    │  │ PublicKey: 04abc123...     │    │
                  │              │        │  │ CachedAt: 2026-01-21       │    │
                  │    HTTP      │        │  └────────────────────────────┘    │
                  │    POST      │        └────────────────────────────────────┘
                  ▼              │                         │
              credential         │                         │
                JSON             │                         ▼
                                 │               ┌────────────────────┐
                                 │               │  Structure Valid?  │
                                 │               │  Issuer Matches?   │
                                 │               │  Not Expired?      │
                                 │               └─────────┬──────────┘
                                 │                         │
                                 │                         ▼
                                 │               ┌────────────────────┐
                                 │               │  verificationStatus│
                                 │               │     "SUCCESS"      │
                                 │               │  verificationLevel │
                                 │               │  "TRUSTED_ISSUER"  │
                                 ◀───────────────└────────────────────┘


┌─────────────────────────────────────────────────────────────────────────────┐
│                         ISSUER SYNC DATA FLOW                               │
│                    (Required before going offline)                          │
└─────────────────────────────────────────────────────────────────────────────┘

┌────────┐    ┌────────┐    ┌────────┐    ┌────────┐    ┌────────┐
│  POST  │───▶│Adapter │───▶│ Agent  │───▶│Polygon │───▶│ Cache  │
│ /sync  │    │        │    │  API   │    │  RPC   │    │ Update │
│        │    │        │    │        │    │        │    │        │
└────────┘    └────────┘    └────────┘    └────────┘    └────────┘
     │             │             │             │             │
     │             │             │             │             │
     ▼             ▼             ▼             ▼             ▼
  { "did":    Resolve DID   GET /dids/   eth_call()     issuer-cache.json
   "did:..."  via Agent     {did}        getDID()       updated
  }
```

---

## 5. Adapter Service Architecture

### 5.1 Overview

The **Verification Adapter** is the key innovation in this PoC. It sits between the Inji Verify UI and the verification backends, providing:

1. **Unified Verification Endpoint** - Single API for all credential types
2. **Intelligent Routing** - Routes to appropriate backend based on DID method
3. **Offline Capability** - Caches issuer information for disconnected verification
4. **Graceful Degradation** - Falls back to trusted issuer mode when full crypto isn't possible

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                      VERIFICATION ADAPTER ARCHITECTURE                      │
└─────────────────────────────────────────────────────────────────────────────┘

                              ┌─────────────────────────────────────┐
                              │         INJI VERIFY UI              │
                              │       (nginx proxy)                 │
                              └─────────────────┬───────────────────┘
                                                │
                                    POST /v1/verify/vc-verification
                                                │
                                                ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│                        VERIFICATION ADAPTER (:8085)                          │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                         REQUEST HANDLER                                 │ │
│  │                                                                         │ │
│  │   • Parse credential from multiple formats                              │ │
│  │   • Extract issuer DID and proof type                                   │ │
│  │   • Determine verification strategy                                     │ │
│  │                                                                         │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                    │                                         │
│                                    ▼                                         │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                      CONNECTIVITY DETECTOR                              │ │
│  │                                                                         │ │
│  │   • Ping CREDEBL Agent                                                  │ │
│  │   • Ping Inji Verify Service                                            │ │
│  │   • Determine online/offline status                                     │ │
│  │                                                                         │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                    │                                         │
│              ┌─────────────────────┼─────────────────────┐                  │
│              │                     │                     │                  │
│              ▼                     ▼                     ▼                  │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐          │
│  │   ONLINE MODE    │  │  OFFLINE MODE    │  │  HYBRID MODE     │          │
│  │                  │  │                  │  │                  │          │
│  │ did:polygon →    │  │ All DIDs →       │  │ Ed25519Sig2020   │          │
│  │   CREDEBL Agent  │  │   Local Cache    │  │ + Cached Issuer  │          │
│  │                  │  │                  │  │ → Offline Path   │          │
│  │ did:web/key →    │  │ Verify:          │  │                  │          │
│  │   Inji Verify    │  │ • Structure      │  │ (Avoids w3id.org │          │
│  │                  │  │ • Issuer match   │  │  context fetch)  │          │
│  └────────┬─────────┘  │ • Expiration     │  └──────────────────┘          │
│           │            └────────┬─────────┘                                 │
│           │                     │                                           │
│           ▼                     ▼                                           │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │                         ISSUER CACHE                                  │  │
│  │                                                                       │  │
│  │   ┌─────────────────────────────────────────────────────────────┐    │  │
│  │   │  issuer-cache.json                                           │    │  │
│  │   │  {                                                           │    │  │
│  │   │    "issuers": {                                              │    │  │
│  │   │      "did:polygon:0xD3A...": {                               │    │  │
│  │   │        "didDocument": {...},                                 │    │  │
│  │   │        "publicKeyHex": "04abc...",                           │    │  │
│  │   │        "keyType": "secp256k1",                               │    │  │
│  │   │        "cachedAt": 1737489600000                             │    │  │
│  │   │      }                                                       │    │  │
│  │   │    }                                                         │    │  │
│  │   │  }                                                           │    │  │
│  │   └─────────────────────────────────────────────────────────────┘    │  │
│  │                                                                       │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │                      CONTEXT PROXY (:8086)                            │  │
│  │                                                                       │  │
│  │   Serves cached JSON-LD contexts for offline use:                     │  │
│  │   • /security/suites/ed25519-2020/v1 → ed25519-2020.jsonld           │  │
│  │   • /2018/credentials/v1 → credentials-v1.json                        │  │
│  │                                                                       │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 5.2 Design Decisions

#### Why an Adapter Instead of Alternatives?

| Approach | Description | Pros | Cons | Decision |
|----------|-------------|------|------|----------|
| **Adapter Service** | Proxy between UI and backends | Flexible routing, offline support, no upstream changes | Additional component | ✅ **CHOSEN** |
| Modify Inji Verify | Add polygon support to Inji codebase | Native integration | Requires fork maintenance, complex | ❌ Rejected |
| Modify CREDEBL Agent | Add all verification logic to agent | Single backend | Agent doesn't support all DID methods | ❌ Rejected |
| Client-side verification | Verify in browser/mobile | True offline | Complex, security concerns, limited crypto | ❌ Rejected |

#### Key Design Choices

1. Stateless Request Handling

- Each request is independent
- No session management required
- Horizontally scalable

2. File-based Issuer Cache

- Simple JSON file storage
- Survives container restarts
- Easy to inspect and modify
- Can be pre-populated before deployment

3. Trusted Issuer Fallback

- When full cryptographic verification isn't possible (e.g., Ed25519Signature2020 requires JSON-LD canonicalization)
- Falls back to structural validation + issuer cache lookup
- Provides reasonable assurance for offline scenarios
- Clearly indicates verification level in response

4. DID Method Routing

```javascript
// Routing logic
if (didMethod === 'did:polygon') {
    return verifyViaCredeblAgent(credential);  // Full crypto verification
} else {
    return verifyViaInjiVerify(credential);    // Delegate to Inji
}
```

5. Ed25519Signature2020 Special Handling

- If Inji Verify can't fetch w3id.org contexts (network issues)
- If issuer is cached, route to offline verification
- Avoids unnecessary network dependency

### 5.3 Component Details

#### Issuer Cache Manager

```javascript
class IssuerCache {
    constructor(cacheFile) {
        this.cacheFile = cacheFile;
        this.cache = this.load();
    }

    // Get cached issuer (returns null if expired)
    get(did) {
        const entry = this.cache.issuers[did];
        if (!entry) return null;
        if (Date.now() - entry.cachedAt > CACHE_TTL) return null;
        return entry;
    }

    // Cache issuer DID document and public key
    set(did, didDocument, keyType, publicKeyHex) {
        this.cache.issuers[did] = {
            did, didDocument, keyType, publicKeyHex,
            cachedAt: Date.now()
        };
        this.save();
    }
}
```

#### Connectivity Detector

```javascript
async function checkConnectivity() {
    const checks = [
        pingUrl(CREDEBL_AGENT_URL + '/agent'),
        pingUrl(INJI_VERIFY_URL + '/v1/verify/actuator/health')
    ];

    const results = await Promise.allSettled(checks);
    return results.some(r => r.status === 'fulfilled' && r.value);
}
```

#### Verification Flow Controller

```javascript
async function verifyCredential(credential, forceOffline = false) {
    const issuer = credential.issuer?.id || credential.issuer;
    const didMethod = extractDidMethod(issuer);
    const proofType = credential.proof?.type;

    const online = forceOffline ? false : await checkConnectivity();

    // Special handling: Ed25519Signature2020 with cached issuer
    if (online && proofType === 'Ed25519Signature2020' &&
        (didMethod === 'did:web' || didMethod === 'did:key')) {
        if (issuerCache.get(issuer)) {
            return verifyOffline(credential, issuer, didMethod);
        }
    }

    if (online) {
        return verifyOnline(credential, didMethod);
    } else {
        return verifyOffline(credential, issuer, didMethod);
    }
}
```

---

## 6. Endpoints Reference

### 6.1 Verification Adapter Endpoints

| Endpoint | Method | Storyboard Phase | Description |
|----------|--------|------------------|-------------|
| `/health` | GET | - | Health check, returns connectivity status and cache stats |
| `/cache` | GET | 4.2 (Offline Setup) | View all cached issuers |
| `/sync` | POST | 4.2 (Offline Setup) | Sync issuer(s) to local cache |
| `/verify-offline` | POST | 4.2 (Offline Verify) | Force offline verification |
| `/v1/verify/vc-verification` | POST | 4.1, 4.2 (Verify) | Main verification endpoint (auto online/offline) |

### 6.2 CREDEBL Platform Endpoints

| Endpoint | Method | Storyboard Phase | Description |
|----------|--------|------------------|-------------|
| `/api/v1/auth/signup` | POST | 1.1 (Admin Onboard) | Register new user |
| `/api/v1/organizations` | POST | 1.2 (Org Create) | Create organization |
| `/api/v1/organizations/{id}/agents` | POST | 1.3 (Agent Setup) | Provision dedicated agent |
| `/api/v1/schemas` | POST | 1.4 (Schema) | Create credential schema |
| `/api/v1/credentials/offer` | POST | 2.2 (Issue) | Issue credential offer |

### 6.3 Credo Agent Endpoints

| Endpoint | Method | Storyboard Phase | Description |
|----------|--------|------------------|-------------|
| `/agent/token` | POST | 4.1 (Verify) | Get JWT token for agent auth |
| `/agent/credential/issue` | POST | 2.2 (Issue) | Issue W3C credential |
| `/agent/credential/verify` | POST | 4.1 (Online Verify) | Verify credential signature |
| `/dids/{did}` | GET | 4.2 (Sync) | Resolve DID document |

### 6.4 Inji Verify Service Endpoints

| Endpoint | Method | Storyboard Phase | Description |
|----------|--------|------------------|-------------|
| `/v1/verify/vc-verification` | POST | 4.1 (Online Verify) | Verify did:web/key credentials |
| `/v1/verify/actuator/health` | GET | - | Health check |

### 6.5 Endpoint Flow Diagrams

#### Credential Issuance Flow

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│ ISSUANCE ENDPOINTS FLOW (Phase 2.2)                                         │
└─────────────────────────────────────────────────────────────────────────────┘

    ISSUER                 API GATEWAY              ISSUANCE SERVICE           AGENT
      │                        │                          │                      │
      │  POST /api/v1/         │                          │                      │
      │  credentials/offer     │                          │                      │
      │───────────────────────▶│                          │                      │
      │                        │   Forward to             │                      │
      │                        │   issuance service       │                      │
      │                        │─────────────────────────▶│                      │
      │                        │                          │  POST /agent/        │
      │                        │                          │  credential/issue    │
      │                        │                          │─────────────────────▶│
      │                        │                          │                      │
      │                        │                          │  Signed Credential   │
      │                        │                          │◀─────────────────────│
      │                        │                          │                      │
      │                        │  Credential Response     │                      │
      │                        │◀─────────────────────────│                      │
      │  Credential JSON       │                          │                      │
      │◀───────────────────────│                          │                      │
      │                        │                          │                      │
```

#### Online Verification Flow

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│ ONLINE VERIFICATION ENDPOINTS FLOW (Phase 4.1)                              │
└─────────────────────────────────────────────────────────────────────────────┘

    VERIFIER              INJI UI              ADAPTER                AGENT
       │                     │                    │                     │
       │  Scan QR            │                    │                     │
       │────────────────────▶│                    │                     │
       │                     │                    │                     │
       │                     │  POST /v1/verify/  │                     │
       │                     │  vc-verification   │                     │
       │                     │───────────────────▶│                     │
       │                     │                    │                     │
       │                     │                    │  Check connectivity │
       │                     │                    │  ──────────────────▶│
       │                     │                    │  Online ✓           │
       │                     │                    │◀──────────────────  │
       │                     │                    │                     │
       │                     │                    │  POST /agent/token  │
       │                     │                    │────────────────────▶│
       │                     │                    │  JWT Token          │
       │                     │                    │◀────────────────────│
       │                     │                    │                     │
       │                     │                    │  POST /agent/       │
       │                     │                    │  credential/verify  │
       │                     │                    │────────────────────▶│
       │                     │                    │                     │
       │                     │                    │  (Agent resolves    │
       │                     │                    │   DID from Polygon) │
       │                     │                    │                     │
       │                     │                    │  { isValid: true }  │
       │                     │                    │◀────────────────────│
       │                     │                    │                     │
       │                     │  { verificationStatus: "SUCCESS" }       │
       │                     │◀───────────────────│                     │
       │  ✓ Valid            │                    │                     │
       │◀────────────────────│                    │                     │
```

#### Offline Verification Flow

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│ OFFLINE VERIFICATION ENDPOINTS FLOW (Phase 4.2)                              │
└─────────────────────────────────────────────────────────────────────────────┘

    VERIFIER              INJI UI              ADAPTER              LOCAL CACHE
       │                     │                    │                      │
       │  Scan QR            │                    │                      │
       │────────────────────▶│                    │                      │
       │                     │                    │                      │
       │                     │  POST /v1/verify/  │                      │
       │                     │  vc-verification   │                      │
       │                     │───────────────────▶│                      │
       │                     │                    │                      │
       │                     │                    │  Check connectivity  │
       │                     │                    │  ────────────────────│
       │                     │                    │  Offline ✗           │
       │                     │                    │◀────────────────────│
       │                     │                    │                      │
       │                     │                    │  Lookup issuer       │
       │                     │                    │─────────────────────▶│
       │                     │                    │                      │
       │                     │                    │  { did, publicKey }  │
       │                     │                    │◀─────────────────────│
       │                     │                    │                      │
       │                     │                    │  Validate structure  │
       │                     │                    │  ───────────────────▶│
       │                     │                    │                      │
       │                     │  { verificationStatus: "SUCCESS",         │
       │                     │    offline: true,                         │
       │                     │    verificationLevel: "TRUSTED_ISSUER" }  │
       │                     │◀───────────────────│                      │
       │  ✓ Valid (Offline)  │                    │                      │
       │◀────────────────────│                    │                      │
```

---

## 7. Deployment Architecture

### 7.1 Container Architecture

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                         DOCKER COMPOSE DEPLOYMENT                           │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                              DOCKER NETWORK                                 │
│                          (docker-deployment_default)                        │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                        EXTERNAL ACCESS                              │    │
│  │   :3000 (UI) :3001 (Inji) :5001 (API) :8085 (Adapter) :8004 (Agent) │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                    │                                        │
│  ┌────────────────┬────────────────┼────────────────┬────────────────┐      │
│  │                │                │                │                │      │
│  ▼                ▼                ▼                ▼                ▼      │
│ ┌──────┐      ┌──────┐      ┌──────────┐      ┌──────┐      ┌──────────┐    │
│ │UI App│      │ Inji │      │Verif.    │      │  API │      │  Credo   │    │
│ │:3000 │      │Verify│      │Adapter   │      │Gateway│     │  Agent   │    │
│ │      │      │:3001 │      │:8085     │      │:5001 │      │:8004     │    │
│ └──────┘      └──┬───┘      └────┬─────┘      └──┬───┘      └────┬─────┘    │
│                  │               │               │               │          │
│                  │               │               │               │          │
│  ┌───────────────┴───────────────┴───────────────┴───────────────┘          │
│  │                         INTERNAL SERVICES                      │         │
│  │                                                                │         │
│  │  ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐   │         │
│  │  │ user-svc   │ │ org-svc    │ │issuance-svc│ │verif-svc   │   │         │
│  │  └────────────┘ └────────────┘ └────────────┘ └────────────┘   │         │
│  │  ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐   │         │
│  │  │connect-svc │ │webhook-svc │ │ledger-svc  │ │notify-svc  │   │         │
│  │  └────────────┘ └────────────┘ └────────────┘ └────────────┘   │         │
│  │  ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐   │         │
│  │  │agent-prov  │ │cloud-wallet│ │geolocation │ │utility-svc │   │         │
│  │  └────────────┘ └────────────┘ └────────────┘ └────────────┘   │         │
│  │                                                                │         │
│  └────────────────────────────────────────────────────────────────┘         │
│                                    │                                        │
│  ┌─────────────────────────────────┴─────────────────────────────────┐      │
│  │                        DATA STORES                                │      │
│  │                                                                   │      │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐             │      │
│  │  │  PostgreSQL  │  │    Redis     │  │     NATS     │             │      │
│  │  │    :5433     │  │    :6381     │  │    :4222     │             │      │
│  │  │              │  │              │  │              │             │      │
│  │  │ • users      │  │ • sessions   │  │ • pub/sub    │             │      │
│  │  │ • orgs       │  │ • cache      │  │ • events     │             │      │
│  │  │ • credentials│  │              │  │              │             │      │
│  │  └──────────────┘  └──────────────┘  └──────────────┘             │      │
│  │                                                                   │      │
│  │  ┌──────────────┐  ┌──────────────┐                               │      │
│  │  │   Keycloak   │  │    MinIO     │                               │      │
│  │  │    :8081     │  │    :9000     │                               │      │
│  │  │              │  │              │                               │      │
│  │  │ • auth/SSO   │  │ • file store │                               │      │
│  │  └──────────────┘  └──────────────┘                               │      │
│  │                                                                    │     │
│  └────────────────────────────────────────────────────────────────────┘     │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 7.2 Port Reference

| Port | Service | Purpose |
|------|---------|---------|
| 3000 | CREDEBL UI | Admin dashboard |
| 3001 | Inji Verify UI | Credential verification UI |
| 5001 | API Gateway | Platform API |
| 8004 | Credo Agent | Agent HTTP API |
| 9004 | Credo Agent | Agent Admin API |
| 8085 | Verification Adapter | Verification endpoint |
| 8086 | Context Proxy | JSON-LD context cache |
| 8081 | Keycloak | SSO authentication |
| 5433 | PostgreSQL | Platform database |
| 6381 | Redis | Cache and sessions |
| 4222 | NATS | Message queue |
| 9000 | MinIO | Object storage |

### 7.3 Offline Deployment Preparation

```bash
# Before going offline, sync required issuers:

# 1. Check current cache
curl http://localhost:8085/cache | jq '.issuers[].did'

# 2. Sync additional issuers
curl -X POST http://localhost:8085/sync \
  -H "Content-Type: application/json" \
  -d '{
    "dids": [
      "did:polygon:0xD3A288e4cCeb5ADE57c5B674475d6728Af3bD9Fd",
      "did:web:mosip.github.io:inji-config:collab:tan"
    ]
  }'

# 3. Verify cache is populated
curl http://localhost:8085/cache | jq '.totalIssuers'

# 4. Test offline verification
curl -X POST http://localhost:8085/verify-offline \
  -H "Content-Type: application/json" \
  -d @credential.json
```

---

## Appendix A: Glossary

| Term | Definition |
|------|------------|
| **DID** | Decentralized Identifier - a globally unique identifier that does not require a centralized authority |
| **Verifiable Credential** | A tamper-evident credential with cryptographic proof of authorship |
| **Issuer** | Entity that creates and signs credentials |
| **Holder** | Entity that possesses credentials in their wallet |
| **Verifier** | Entity that requests and validates credentials |
| **JSON-LD** | JSON for Linking Data - format for linked data using JSON |
| **Proof** | Cryptographic signature proving credential authenticity |
| **did:polygon** | DID method using Polygon blockchain for DID document storage |
| **did:web** | DID method using web domains for DID document hosting |
| **W3C VC** | W3C Verifiable Credentials standard |

## Appendix B: References

- [W3C Verifiable Credentials Data Model](https://www.w3.org/TR/vc-data-model/)
- [W3C Decentralized Identifiers (DIDs)](https://www.w3.org/TR/did-core/)
- [CREDEBL Platform](https://github.com/credebl/platform)
- [Credo (Aries Framework JavaScript)](https://github.com/openwallet-foundation/credo-ts)
- [Inji Verify](https://github.com/mosip/inji-verify)
- [Polygon DID Method](https://github.com/ayanworks/polygon-did-registrar)
