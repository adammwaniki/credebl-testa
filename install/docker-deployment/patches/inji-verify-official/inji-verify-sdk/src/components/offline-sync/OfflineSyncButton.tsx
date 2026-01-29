/**
 * OfflineSyncButton - Floating action button for offline sync
 *
 * Shows online/offline status and opens the sync panel when clicked.
 * Displays badge with cached issuer count.
 */

import React from 'react';
import { OfflineSyncButtonProps } from './OfflineSync.types';
import './OfflineSync.css';

const OfflineSyncButton: React.FC<OfflineSyncButtonProps> = ({
  onClick,
  isOnline,
  issuerCount
}) => {
  return (
    <button
      className={`offline-sync-button ${isOnline ? 'online' : 'offline'}`}
      onClick={onClick}
      title={isOnline ? 'Online - Click to manage offline data' : 'Offline - Using cached data'}
      aria-label="Open offline sync panel"
    >
      <span className="sync-icon">
        {isOnline ? '⚡' : '📴'}
      </span>
      {issuerCount > 0 && (
        <span className="badge">{issuerCount}</span>
      )}
    </button>
  );
};

export default OfflineSyncButton;
