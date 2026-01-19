"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.PolygonDidResolver = void 0;
const polygon_did_resolver_1 = require("@ayanworks/polygon-did-resolver");
const core_1 = require("@credo-ts/core");
const did_resolver_1 = require("did-resolver");
const didPolygonUtil_1 = require("./didPolygonUtil");
class PolygonDidResolver {
    constructor() {
        this.allowsCaching = true;
        this.allowsLocalDidRecord = true;
        this.supportedMethods = ['polygon'];
        this.resolver = new did_resolver_1.Resolver((0, polygon_did_resolver_1.getResolver)());
    }
    async resolve(agentContext, didUrl) {
        agentContext.config.logger.info(`PolygonDidResolver.resolve called with: ${didUrl}`);
        const didDocumentMetadata = {};

        // Strip fragment (e.g., #key-1) from DID URL to get base DID
        const did = didUrl.split('#')[0];

        // The underlying polygon-did-resolver only accepts DIDs without network prefix for mainnet
        // Transform: did:polygon:mainnet:0xD3A... -> did:polygon:0xD3A...
        // Keep: did:polygon:testnet:0xD3A... as is
        const didForResolver = did.replace(':mainnet:', ':');

        if (!(0, didPolygonUtil_1.isValidPolygonDid)(didForResolver)) {
            agentContext.config.logger.error(`PolygonDidResolver: Invalid DID: ${did}`);
            return {
                didDocument: null,
                didDocumentMetadata,
                didResolutionMetadata: {
                    error: 'invalidDid',
                    message: `Invalid DID: ${did}`,
                },
            };
        }

        try {
            agentContext.config.logger.info(`PolygonDidResolver: Resolving from blockchain: ${didForResolver}`);

            const { didDocument, didDocumentMetadata: resolvedMetadata, didResolutionMetadata } = await this.resolver.resolve(didForResolver);

            agentContext.config.logger.info(`PolygonDidResolver: Blockchain response received`);

            if (!didDocument) {
                agentContext.config.logger.error(`PolygonDidResolver: No document found for ${did}`);
                return {
                    didDocument: null,
                    didDocumentMetadata,
                    didResolutionMetadata: {
                        error: 'notFound',
                        message: `DID document not found for ${did}`,
                    },
                };
            }

            agentContext.config.logger.info(`PolygonDidResolver: Document found, checking verification methods`);

            // Transform verification methods to include publicKeyBase58 if they have blockchainAccountId
            if (didDocument.verificationMethod) {
                const didRepository = agentContext.dependencyManager.resolve(core_1.DidRepository);

                try {
                    agentContext.config.logger.info(`PolygonDidResolver: Looking up local DID record for ${didForResolver}`);

                    // Try to find the DID record - check multiple formats
                    let createdDidRecord = await didRepository.findCreatedDid(agentContext, didForResolver);
                    agentContext.config.logger.info(`PolygonDidResolver: Found record for ${didForResolver}: ${!!createdDidRecord}`);

                    if (!createdDidRecord && didDocument.id) {
                        createdDidRecord = await didRepository.findCreatedDid(agentContext, didDocument.id);
                        agentContext.config.logger.info(`PolygonDidResolver: Found record for ${didDocument.id}: ${!!createdDidRecord}`);
                    }
                    if (!createdDidRecord && did !== didForResolver) {
                        createdDidRecord = await didRepository.findCreatedDid(agentContext, did);
                        agentContext.config.logger.info(`PolygonDidResolver: Found record for ${did}: ${!!createdDidRecord}`);
                    }

                    if (createdDidRecord?.didDocument?.verificationMethod) {
                        const createdVMs = createdDidRecord.didDocument.verificationMethod;
                        agentContext.config.logger.info(`PolygonDidResolver: Local record has ${createdVMs.length} verification methods`);

                        for (let i = 0; i < didDocument.verificationMethod.length; i++) {
                            const vm = didDocument.verificationMethod[i];
                            agentContext.config.logger.info(`PolygonDidResolver: VM ${i}: blockchainAccountId=${!!vm.blockchainAccountId}, publicKeyBase58=${!!vm.publicKeyBase58}`);

                            if (vm.blockchainAccountId && !vm.publicKeyBase58) {
                                const matchingVM = createdVMs.find(cvm => cvm.publicKeyBase58);
                                if (matchingVM?.publicKeyBase58) {
                                    didDocument.verificationMethod[i].publicKeyBase58 = matchingVM.publicKeyBase58;
                                    delete didDocument.verificationMethod[i].blockchainAccountId;
                                    agentContext.config.logger.info(`PolygonDidResolver: Added publicKeyBase58 to VM ${i}`);
                                }
                            }
                        }
                    } else {
                        agentContext.config.logger.warn(`PolygonDidResolver: No local DID record found with verification methods`);
                    }
                } catch (error) {
                    agentContext.config.logger.error(`PolygonDidResolver: Error looking up DID record: ${error.message}`);
                }
            }

            agentContext.config.logger.info(`PolygonDidResolver: Returning resolved document`);
            return {
                didDocument: core_1.JsonTransformer.fromJSON(didDocument, core_1.DidDocument),
                didDocumentMetadata: resolvedMetadata,
                didResolutionMetadata,
            };
        }
        catch (error) {
            agentContext.config.logger.error(`PolygonDidResolver error: ${error.message}`);
            return {
                didDocument: null,
                didDocumentMetadata,
                didResolutionMetadata: {
                    error: 'notFound',
                    message: `resolver_error: Unable to resolve did '${did}': ${error}`,
                },
            };
        }
    }
}
exports.PolygonDidResolver = PolygonDidResolver;
//# sourceMappingURL=PolygonDidResolver.js.map
