export { default as OpenID4VPVerification } from '././components/openid4vp-verification/OpenID4VPVerification';
export { default as QRCodeVerification } from '././components/qrcode-verification/QRCodeVerification';

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
  canVerifyOffline
} from './utils/offlineVerifier';

export type {
  CachedIssuer,
  OfflineSettings
} from './utils/offlineCache';

export type {
  OfflineVerificationResult
} from './utils/offlineVerifier';