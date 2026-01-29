/**
 * Types for Offline Sync Components
 */

export interface CachedIssuerDisplay {
  did: string;
  keyType: string;
  cachedAt: number;
  publicKeyPreview: string;
}

export interface SyncStatus {
  isOnline: boolean;
  lastSync: number | null;
  issuerCount: number;
  contextCount: number;
  hasTemplates: boolean;
  storageUsed: number;
}

export interface OfflineSyncButtonProps {
  onClick: () => void;
  isOnline: boolean;
  issuerCount: number;
}

export interface OfflineSyncPanelProps {
  isOpen: boolean;
  onClose: () => void;
  adapterUrl: string;
}
