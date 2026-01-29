export { default as OpenID4VPVerification } from '././components/openid4vp-verification/OpenID4VPVerification';
export { default as QRCodeVerification } from '././components/qrcode-verification/QRCodeVerification';

// Offline Sync UI Components
export { OfflineSyncButton, OfflineSyncPanel } from './components/offline-sync';
export type { OfflineSyncButtonProps, OfflineSyncPanelProps, SyncStatus } from './components/offline-sync';

// Offline verification utilities
export {
  IssuerCache,
  TemplateCache,
  OfflineSettingsStore,
  syncIssuer,
  syncTemplates,
  isOnline,
  shouldUseOffline
} from './utils/offlineCache';

export {
  verifyOffline,
  canVerifyOffline,
  getVerificationCapabilities
} from './utils/offlineVerifier';

export {
  BUILTIN_CONTEXTS,
  ContextCache,
  createOfflineDocumentLoader,
  precacheContextsForCredential,
  syncStandardContexts
} from './utils/cachedContexts';

export type {
  CachedIssuer,
  OfflineSettings
} from './utils/offlineCache';

export type {
  OfflineVerificationResult
} from './utils/offlineVerifier';