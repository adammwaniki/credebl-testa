"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.validateSpecCompliantPayload = exports.getSecp256k1DidDoc = exports.failedResult = exports.buildDid = exports.isValidPolygonDid = exports.polygonDidRegex = void 0;
const core_1 = require("@credo-ts/core");
const ethers_1 = require("ethers");
const EcdsaSecp256k1Signature2019_1 = require("../signature-suites/EcdsaSecp256k1Signature2019");

// Fixed regex to accept both mainnet and testnet prefixes
// Valid formats: did:polygon:0x..., did:polygon:mainnet:0x..., did:polygon:testnet:0x...
exports.polygonDidRegex = new RegExp(/^did:polygon(:(mainnet|testnet))?:0x[0-9a-fA-F]{40}$/);
const isValidPolygonDid = (did) => exports.polygonDidRegex.test(did);
exports.isValidPolygonDid = isValidPolygonDid;
function buildDid(method, network, publicKey) {
    const address = (0, ethers_1.computeAddress)('0x' + publicKey);
    if (network === 'mainnet') {
        return `did:${method}:${address}`;
    }
    return `did:${method}:${network}:${address}`;
}
exports.buildDid = buildDid;
function failedResult(reason) {
    return {
        didDocumentMetadata: {},
        didRegistrationMetadata: {},
        didState: {
            state: 'failed',
            reason: reason,
        },
    };
}
exports.failedResult = failedResult;
function getSecp256k1DidDoc(did, key, serviceEndpoint) {
    const verificationMethod = (0, core_1.getEcdsaSecp256k1VerificationKey2019)({
        id: `${did}#key-1`,
        key,
        controller: did,
    });
    const didDocumentBuilder = new core_1.DidDocumentBuilder(did);
    didDocumentBuilder.addContext(EcdsaSecp256k1Signature2019_1.SECURITY_CONTEXT_SECP256k1_URL).addVerificationMethod(verificationMethod);
    if (serviceEndpoint) {
        const service = new core_1.DidDocumentService({
            id: `${did}#linked-domain`,
            serviceEndpoint,
            type: 'LinkedDomains',
        });
        didDocumentBuilder.addService(service);
    }
    if (!key.supportsEncrypting && !key.supportsSigning) {
        throw new core_1.CredoError('Key must support at least signing or encrypting');
    }
    if (key.supportsSigning) {
        didDocumentBuilder
            .addAuthentication(verificationMethod.id)
            .addAssertionMethod(verificationMethod.id)
            .addCapabilityDelegation(verificationMethod.id)
            .addCapabilityInvocation(verificationMethod.id);
    }
    if (key.supportsEncrypting) {
        didDocumentBuilder.addKeyAgreement(verificationMethod.id);
    }
    return didDocumentBuilder.build();
}
exports.getSecp256k1DidDoc = getSecp256k1DidDoc;
function validateSpecCompliantPayload(didDocument) {
    var _a;
    // id is required, validated on both compile and runtime
    if (!didDocument.id && !didDocument.id.startsWith('did:polygon:'))
        return 'id is required';
    // verificationMethod is required
    if (!didDocument.verificationMethod)
        return 'verificationMethod is required';
    // verificationMethod must be an array
    if (!Array.isArray(didDocument.verificationMethod))
        return 'verificationMethod must be an array';
    // verificationMethod must be not be empty
    if (!didDocument.verificationMethod.length)
        return 'verificationMethod must be not be empty';
    // verificationMethod types must be supported
    const isValidVerificationMethod = didDocument.verificationMethod.every((vm) => {
        switch (vm.type) {
            case core_1.VERIFICATION_METHOD_TYPE_ECDSA_SECP256K1_VERIFICATION_KEY_2019:
                return (vm === null || vm === void 0 ? void 0 : vm.publicKeyBase58) && (vm === null || vm === void 0 ? void 0 : vm.controller) && (vm === null || vm === void 0 ? void 0 : vm.id);
            default:
                return false;
        }
    });
    if (!isValidVerificationMethod)
        return 'verificationMethod is Invalid';
    if (didDocument.service) {
        const isValidService = didDocument.service
            ? (_a = didDocument === null || didDocument === void 0 ? void 0 : didDocument.service) === null || _a === void 0 ? void 0 : _a.every((s) => {
                return (s === null || s === void 0 ? void 0 : s.serviceEndpoint) && (s === null || s === void 0 ? void 0 : s.id) && (s === null || s === void 0 ? void 0 : s.type);
            })
            : true;
        if (!isValidService)
            return 'Service is Invalid';
    }
    return null;
}
exports.validateSpecCompliantPayload = validateSpecCompliantPayload;
//# sourceMappingURL=didPolygonUtil.js.map
