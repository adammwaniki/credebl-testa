"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.PolygonDidRegistrar = void 0;
const polygon_did_resolver_1 = require("@ayanworks/polygon-did-resolver");
const askar_1 = require("@credo-ts/askar");
const core_1 = require("@credo-ts/core");
const did_resolver_1 = require("did-resolver");
const ethers_1 = require("ethers");
const ledger_1 = require("../ledger");
const didPolygonUtil_1 = require("./didPolygonUtil");
class PolygonDidRegistrar {
    constructor() {
        this.supportedMethods = ['polygon'];
        this.resolver = new did_resolver_1.Resolver((0, polygon_did_resolver_1.getResolver)());
    }
    async create(agentContext, options) {
        const ledgerService = agentContext.dependencyManager.resolve(ledger_1.PolygonLedgerService);
        const didRepository = agentContext.dependencyManager.resolve(core_1.DidRepository);
        const privateKey = options.secret.privateKey;
        const privateKeyHex = '0x' + Buffer.from(privateKey).toString('hex');
        const wallet = new ethers_1.Wallet(new ethers_1.SigningKey(privateKeyHex));
        const provider = new ethers_1.JsonRpcProvider(ledgerService.rpcUrl);
        const value = await provider.getBalance(wallet.address);
        if (Number(value) == 0) {
            return {
                didDocumentMetadata: {},
                didRegistrationMetadata: {},
                didState: {
                    state: 'failed',
                    reason: 'Insufficient balance in wallet',
                },
            };
        }

        // Try to create the key, or retrieve it if it already exists
        let key;
        try {
            key = await agentContext.wallet.createKey({ keyType: core_1.KeyType.K256, privateKey });
            agentContext.config.logger.info('Key created successfully in wallet');
        } catch (error) {
            const errorMessage = error instanceof Error ? error.message : String(error);
            if (errorMessage.toLowerCase().includes('key already exists') || errorMessage.toLowerCase().includes('duplicate')) {
                agentContext.config.logger.info('Key already exists in wallet, deriving key from private key');
                const signingKeyFromPrivate = new ethers_1.SigningKey(privateKeyHex);
                const compressedPublicKeyHex = signingKeyFromPrivate.compressedPublicKey.slice(2);
                const publicKeyBuffer = Buffer.from(compressedPublicKeyHex, 'hex');
                key = core_1.Key.fromPublicKey(publicKeyBuffer, core_1.KeyType.K256);
                agentContext.config.logger.debug(`Using existing key with compressedPublicKey base58: ${core_1.TypedArrayEncoder.toBase58(key.compressedPublicKey)}`);
            } else {
                throw error;
            }
        }

        const publicKeyHex = Buffer.from(key.publicKey).toString('hex');
        // Use the original buildDid which returns did:polygon:0xD3A... for mainnet (no mainnet prefix)
        const did = (0, didPolygonUtil_1.buildDid)(options.method, options.options.network, publicKeyHex);
        agentContext.config.logger.info(`Creating DID on ledger: ${did}`);

        // Create DID document with publicKeyBase58 format AND correct security context
        const secpDidDoc = this.createSecp256k1DidDoc(did, key, options.options.endpoint);

        try {
            const keyNameInWallet = core_1.TypedArrayEncoder.toBase58(key.compressedPublicKey);
            agentContext.config.logger.debug(`Looking up key in wallet with name: ${keyNameInWallet}`);
            const signingKey = await this.getSigningKey(agentContext.wallet, keyNameInWallet);

            const didRegistry = ledgerService.createDidRegistryInstance(signingKey);
            const response = await didRegistry.create(did, secpDidDoc);
            agentContext.config.logger.info(`Published did on ledger: ${did}`);

            const didDocument = core_1.JsonTransformer.fromJSON(secpDidDoc, core_1.DidDocument);
            const didRecord = new core_1.DidRecord({
                did: didDocument.id,
                role: core_1.DidDocumentRole.Created,
                didDocument,
            });
            agentContext.config.logger.info(`Saving DID record to wallet: ${did}`);
            await didRepository.save(agentContext, didRecord);
            return {
                didDocumentMetadata: {},
                didRegistrationMetadata: { txn: response.txnHash },
                didState: {
                    state: 'finished',
                    did: didDocument.id,
                    didDocument: didDocument,
                },
            };
        }
        catch (error) {
            const errorMessage = error instanceof Error ? error.message : 'Unknown error';
            agentContext.config.logger.error(`Error registering DID ${did} : ${errorMessage}`);

            if (errorMessage.toLowerCase().includes('already registered')) {
                agentContext.config.logger.info(`DID ${did} already exists on blockchain, attempting to import...`);
                try {
                    let existingRecord = await didRepository.findCreatedDid(agentContext, did);

                    if (existingRecord && existingRecord.didDocument) {
                        const vm = existingRecord.didDocument.verificationMethod?.[0];
                        // Check if it has publicKeyBase58 AND correct context
                        const hasCorrectContext = existingRecord.didDocument.context?.includes('https://w3id.org/security/suites/secp256k1-2019/v1');
                        if (vm && vm.publicKeyBase58 && hasCorrectContext) {
                            agentContext.config.logger.info(`DID ${did} already exists in wallet with correct format`);
                            return {
                                didDocumentMetadata: {},
                                didRegistrationMetadata: {},
                                didState: {
                                    state: 'finished',
                                    did: existingRecord.didDocument.id,
                                    didDocument: existingRecord.didDocument,
                                },
                            };
                        } else {
                            agentContext.config.logger.info(`Existing DID record has wrong format or missing context, updating...`);
                            await didRepository.delete(agentContext, existingRecord);
                        }
                    }

                    const didDocument = core_1.JsonTransformer.fromJSON(secpDidDoc, core_1.DidDocument);
                    const didRecord = new core_1.DidRecord({
                        did: didDocument.id,
                        role: core_1.DidDocumentRole.Created,
                        didDocument,
                    });
                    await didRepository.save(agentContext, didRecord);
                    agentContext.config.logger.info(`Successfully saved DID ${did} with publicKeyBase58 format and security context`);
                    return {
                        didDocumentMetadata: {},
                        didRegistrationMetadata: {},
                        didState: {
                            state: 'finished',
                            did: didDocument.id,
                            didDocument: didDocument,
                        },
                    };
                } catch (importError) {
                    const importErrorMessage = importError instanceof Error ? importError.message : 'Unknown error';
                    agentContext.config.logger.error(`Failed to import existing DID: ${importErrorMessage}`);
                }
            }

            return {
                didDocumentMetadata: {},
                didRegistrationMetadata: {},
                didState: {
                    state: 'failed',
                    reason: `unknownError: ${errorMessage}`,
                },
            };
        }
    }

    createSecp256k1DidDoc(did, key, endpoint) {
        const publicKeyBase58 = core_1.TypedArrayEncoder.toBase58(key.publicKey);
        // CRITICAL: Include the secp256k1 security context so publicKeyBase58 is preserved during JSON-LD framing
        const didDoc = {
            "@context": [
                "https://www.w3.org/ns/did/v1",
                "https://w3id.org/security/suites/secp256k1-2019/v1"
            ],
            "id": did,
            "verificationMethod": [{
                "id": `${did}#key-1`,
                "type": "EcdsaSecp256k1VerificationKey2019",
                "controller": did,
                "publicKeyBase58": publicKeyBase58
            }],
            "authentication": [`${did}#key-1`],
            "assertionMethod": [`${did}#key-1`]
        };
        if (endpoint) {
            didDoc.service = [{
                "id": `${did}#service-1`,
                "serviceEndpoint": endpoint,
                "type": "DIDCommMessaging"
            }];
        }
        return didDoc;
    }

    async update(agentContext, options) {
        var _a, _b, _c, _d, _e;
        const ledgerService = agentContext.dependencyManager.resolve(ledger_1.PolygonLedgerService);
        const didRepository = agentContext.dependencyManager.resolve(core_1.DidRepository);
        let didDocument;
        let didRecord;
        try {
            const isValidDidDoc = (0, didPolygonUtil_1.validateSpecCompliantPayload)(options.didDocument);
            if (options.didDocument && isValidDidDoc === null) {
                didDocument = options.didDocument;
                const resolvedDocument = await this.resolver.resolve(didDocument.id);
                didRecord = await didRepository.findCreatedDid(agentContext, didDocument.id);
                if (!resolvedDocument.didDocument || resolvedDocument.didDocumentMetadata.deactivated || !didRecord) {
                    return {
                        didDocumentMetadata: {},
                        didRegistrationMetadata: {},
                        didState: { state: 'failed', reason: 'Did not found' },
                    };
                }
                if ((_a = options?.secret)?.privateKey) {
                    const privateKey = (_b = options?.secret)?.privateKey;
                    const privateKeyHex = '0x' + Buffer.from(privateKey).toString('hex');
                    if (privateKey && !(0, core_1.isValidPrivateKey)(privateKey, core_1.KeyType.K256)) {
                        return {
                            didDocumentMetadata: {},
                            didRegistrationMetadata: {},
                            didState: { state: 'failed', reason: 'Invalid private key provided' },
                        };
                    }
                    let key;
                    try {
                        key = await agentContext.wallet.createKey({ keyType: core_1.KeyType.K256, privateKey });
                    } catch (error) {
                        const errorMessage = error instanceof Error ? error.message : String(error);
                        if (errorMessage.toLowerCase().includes('key already exists') || errorMessage.toLowerCase().includes('duplicate')) {
                            const signingKeyFromPrivate = new ethers_1.SigningKey(privateKeyHex);
                            const compressedPublicKeyHex = signingKeyFromPrivate.compressedPublicKey.slice(2);
                            const publicKeyBuffer = Buffer.from(compressedPublicKeyHex, 'hex');
                            key = core_1.Key.fromPublicKey(publicKeyBuffer, core_1.KeyType.K256);
                        } else {
                            throw error;
                        }
                    }
                    const verificationMethodCount = (_d = (_c = didDocument?.verificationMethod)?.length) ?? 0;
                    const verificationMethod = (0, core_1.getEcdsaSecp256k1VerificationKey2019)({
                        id: `${didDocument.id}#key-${verificationMethodCount + 1}`,
                        key,
                        controller: didDocument.id,
                    });
                    didDocument.verificationMethod = [...((_e = didDocument?.verificationMethod) ?? []), verificationMethod];
                }
            } else {
                return {
                    didDocumentMetadata: {},
                    didRegistrationMetadata: {},
                    didState: { state: 'failed', reason: isValidDidDoc ?? 'Provide a valid didDocument' },
                };
            }
            if (!didRecord) {
                return {
                    didDocumentMetadata: {},
                    didRegistrationMetadata: {},
                    didState: { state: 'failed', reason: 'DidRecord not found in wallet' },
                };
            }
            const publicKeyBase58 = await this.getPublicKeyFromDid(agentContext, options.did);
            if (!publicKeyBase58) {
                throw new core_1.CredoError('Public Key not found in wallet');
            }
            const signingKey = await this.getSigningKey(agentContext.wallet, publicKeyBase58);
            const didRegistry = ledgerService.createDidRegistryInstance(signingKey);
            const response = await didRegistry.update(didDocument.id, didDocument);
            if (!response) {
                throw new Error('Unable to update did document');
            }
            didRecord.didDocument = didDocument;
            await didRepository.update(agentContext, didRecord);
            return {
                didDocumentMetadata: {},
                didRegistrationMetadata: { txn: response.txnHash },
                didState: { state: 'finished', did: didDocument.id, didDocument },
            };
        } catch (error) {
            const errorMessage = error instanceof Error ? error.message : 'Unknown error';
            agentContext.config.logger.error(`Error updating DID ${options.did} : ${errorMessage}`);
            return {
                didDocumentMetadata: {},
                didRegistrationMetadata: {},
                didState: { state: 'failed', reason: `unknownError: ${errorMessage}` },
            };
        }
    }

    async deactivate(agentContext, options) {
        const ledgerService = agentContext.dependencyManager.resolve(ledger_1.PolygonLedgerService);
        const didRepository = agentContext.dependencyManager.resolve(core_1.DidRepository);
        try {
            const didRecord = await didRepository.findCreatedDid(agentContext, options.did);
            const resolvedDocument = await this.resolver.resolve(options.did);
            if (!resolvedDocument.didDocument || resolvedDocument.didDocumentMetadata.deactivated || !didRecord) {
                return {
                    didDocumentMetadata: {},
                    didRegistrationMetadata: {},
                    didState: { state: 'failed', reason: 'Did not found' },
                };
            }
            const publicKeyBase58 = await this.getPublicKeyFromDid(agentContext, options.did);
            if (!publicKeyBase58) {
                throw new core_1.CredoError('Public Key not found in wallet');
            }
            const signingKey = await this.getSigningKey(agentContext.wallet, publicKeyBase58);
            const didRegistry = ledgerService.createDidRegistryInstance(signingKey);
            const response = await didRegistry.revoke(options.did);
            if (!response) {
                return {
                    didDocumentMetadata: {},
                    didRegistrationMetadata: {},
                    didState: { state: 'failed', reason: 'Did not deactivated' },
                };
            }
            await didRepository.delete(agentContext, didRecord);
            return {
                didDocumentMetadata: {},
                didRegistrationMetadata: { txn: response },
                didState: { state: 'finished', did: options.did },
            };
        } catch (error) {
            const errorMessage = error instanceof Error ? error.message : 'Unknown error';
            agentContext.config.logger.error(`Error deactivating DID ${options.did} : ${errorMessage}`);
            return {
                didDocumentMetadata: {},
                didRegistrationMetadata: {},
                didState: { state: 'failed', reason: `unknownError: ${errorMessage}` },
            };
        }
    }

    async getSigningKey(wallet, publicKeyBase58) {
        if (!(wallet instanceof askar_1.AskarWallet)) {
            throw new core_1.CredoError('Expected wallet to be instance of AskarWallet');
        }
        const keyEntry = await wallet.withSession(async (session) => {
            return session.fetchKey({ name: publicKeyBase58 });
        });
        if (!keyEntry || !keyEntry.key) {
            throw new core_1.CredoError(`Key entry not found for publicKeyBase58: ${publicKeyBase58}`);
        }
        const privateKeyBytes = keyEntry.key.secretBytes;
        const privateKeyHex = '0x' + Buffer.from(privateKeyBytes).toString('hex');
        return new ethers_1.SigningKey(privateKeyHex);
    }

    async getPublicKeyFromDid(agentContext, did) {
        const didRecord = await agentContext.dependencyManager
            .resolve(core_1.DidRepository)
            .findCreatedDid(agentContext, did);
        if (!didRecord) return;
        const verificationMethod = didRecord.didDocument?.verificationMethod?.[0];
        if (!verificationMethod) return;
        return verificationMethod.publicKeyBase58;
    }
}
exports.PolygonDidRegistrar = PolygonDidRegistrar;
//# sourceMappingURL=PolygonDidRegistrar.js.map
