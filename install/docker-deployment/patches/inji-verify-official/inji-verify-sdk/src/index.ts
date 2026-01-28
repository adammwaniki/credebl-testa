export { default as OpenID4VPVerification } from '././components/openid4vp-verification/OpenID4VPVerification';
export { default as QRCodeVerification } from '././components/qrcode-verification/QRCodeVerification';

// Offline verification utilities
export {
  IssuerCache,
  TemplateCache,
  OfflineSettingsStore,
  syncIssuer,
  syncTemplates,
  syncStandardContexts,
  syncContextsFromCredential,
  isOnline,
  shouldUseOffline
} from './utils/offlineCache';

export {
  verifyOffline,
  canVerifyOffline,
  getVerificationCapabilities
} from './utils/offlineVerifier';

export {
  ContextCache,
  createOfflineDocumentLoader,
  extractContextUrls,
  precacheContextsForCredential,
  BUILTIN_CONTEXTS
} from './utils/cachedContexts';

export type {
  CachedIssuer,
  OfflineSettings
} from './utils/offlineCache';

export type {
  OfflineVerificationResult
} from './utils/offlineVerifier';