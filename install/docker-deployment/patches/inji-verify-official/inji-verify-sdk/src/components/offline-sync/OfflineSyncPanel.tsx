/**
 * OfflineSyncPanel - Drawer panel for managing offline sync data
 *
 * Allows users to:
 * - View and manage cached issuers
 * - Add new issuers to sync
 * - View cached contexts and templates
 * - Sync all data or clear cache
 */

import React, { useState, useEffect, useCallback } from 'react';
import { OfflineSyncPanelProps, CachedIssuerDisplay, SyncStatus } from './OfflineSync.types';
import {
  IssuerCache,
  TemplateCache,
  OfflineSettingsStore,
  syncIssuer,
  syncTemplates,
  isOnline
} from '../../utils/offlineCache';
import { ContextCache, syncStandardContexts, BUILTIN_CONTEXTS } from '../../utils/cachedContexts';
import './OfflineSync.css';

const OfflineSyncPanel: React.FC<OfflineSyncPanelProps> = ({
  isOpen,
  onClose,
  adapterUrl
}) => {
  const [status, setStatus] = useState<SyncStatus>({
    isOnline: true,
    lastSync: null,
    issuerCount: 0,
    contextCount: 0,
    hasTemplates: false,
    storageUsed: 0
  });
  const [issuers, setIssuers] = useState<CachedIssuerDisplay[]>([]);
  const [newDid, setNewDid] = useState('');
  const [isSyncing, setIsSyncing] = useState(false);
  const [syncError, setSyncError] = useState<string | null>(null);

  // Load current state
  const loadState = useCallback(() => {
    const cachedIssuers = IssuerCache.list();
    const settings = OfflineSettingsStore.get();

    setIssuers(cachedIssuers.map(issuer => ({
      did: issuer.did,
      keyType: issuer.keyType,
      cachedAt: issuer.cachedAt,
      publicKeyPreview: issuer.publicKeyHex
        ? issuer.publicKeyHex.substring(0, 16) + '...'
        : 'N/A'
    })));

    // Estimate storage used (rough calculation)
    let storageUsed = 0;
    try {
      const issuerData = localStorage.getItem('inji-verify-offline-issuers') || '';
      const templateData = localStorage.getItem('inji-verify-jsonxt-templates') || '';
      const contextData = localStorage.getItem('inji-verify-jsonld-contexts') || '';
      storageUsed = issuerData.length + templateData.length + contextData.length;
    } catch (e) {
      // Ignore
    }

    setStatus({
      isOnline: isOnline(),
      lastSync: settings.lastSync,
      issuerCount: cachedIssuers.length,
      contextCount: ContextCache.count(),
      hasTemplates: TemplateCache.get() !== null,
      storageUsed
    });
  }, []);

  useEffect(() => {
    if (isOpen) {
      loadState();
    }
  }, [isOpen, loadState]);

  // Listen for online/offline changes
  useEffect(() => {
    const handleOnline = () => setStatus(s => ({ ...s, isOnline: true }));
    const handleOffline = () => setStatus(s => ({ ...s, isOnline: false }));

    window.addEventListener('online', handleOnline);
    window.addEventListener('offline', handleOffline);

    return () => {
      window.removeEventListener('online', handleOnline);
      window.removeEventListener('offline', handleOffline);
    };
  }, []);

  // Add a new issuer
  const handleAddIssuer = async () => {
    if (!newDid.trim() || !status.isOnline) return;

    setIsSyncing(true);
    setSyncError(null);

    try {
      const success = await syncIssuer(newDid.trim(), adapterUrl);
      if (success) {
        setNewDid('');
        loadState();
      } else {
        setSyncError(`Failed to sync issuer: ${newDid}`);
      }
    } catch (e) {
      setSyncError(e instanceof Error ? e.message : 'Sync failed');
    } finally {
      setIsSyncing(false);
    }
  };

  // Refresh a single issuer
  const handleRefreshIssuer = async (did: string) => {
    if (!status.isOnline) return;

    setIsSyncing(true);
    setSyncError(null);

    try {
      await syncIssuer(did, adapterUrl);
      loadState();
    } catch (e) {
      setSyncError(e instanceof Error ? e.message : 'Refresh failed');
    } finally {
      setIsSyncing(false);
    }
  };

  // Delete a cached issuer
  const handleDeleteIssuer = (did: string) => {
    if (window.confirm(`Remove cached issuer?\n\n${did}`)) {
      IssuerCache.delete(did);
      loadState();
    }
  };

  // Sync all data
  const handleSyncAll = async () => {
    if (!status.isOnline) return;

    setIsSyncing(true);
    setSyncError(null);

    try {
      // Sync templates
      await syncTemplates(adapterUrl);

      // Sync standard contexts
      await syncStandardContexts();

      // Refresh all existing issuers
      for (const issuer of issuers) {
        try {
          await syncIssuer(issuer.did, adapterUrl);
        } catch (e) {
          console.error(`Failed to sync ${issuer.did}:`, e);
        }
      }

      OfflineSettingsStore.setLastSync();
      loadState();
    } catch (e) {
      setSyncError(e instanceof Error ? e.message : 'Sync all failed');
    } finally {
      setIsSyncing(false);
    }
  };

  // Clear all cached data
  const handleClearAll = () => {
    if (window.confirm('Clear all cached offline data?\n\nThis will remove all cached issuers, templates, and contexts.')) {
      IssuerCache.clear();
      TemplateCache.clear();
      ContextCache.clear();
      loadState();
    }
  };

  // Format timestamp
  const formatTime = (timestamp: number | null) => {
    if (!timestamp) return 'Never';
    const date = new Date(timestamp);
    const now = new Date();
    const diff = now.getTime() - timestamp;

    if (diff < 60000) return 'Just now';
    if (diff < 3600000) return `${Math.floor(diff / 60000)} min ago`;
    if (diff < 86400000) return `${Math.floor(diff / 3600000)} hours ago`;
    return date.toLocaleDateString();
  };

  // Format bytes
  const formatBytes = (bytes: number) => {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
  };

  const builtinContextUrls = Object.keys(BUILTIN_CONTEXTS);
  const templateKeys = TemplateCache.get() ? Object.keys(TemplateCache.get() as object) : [];

  return (
    <>
      {/* Overlay */}
      <div
        className={`offline-sync-overlay ${isOpen ? 'open' : ''}`}
        onClick={onClose}
      />

      {/* Panel */}
      <div className={`offline-sync-panel ${isOpen ? 'open' : ''}`}>
        {/* Header */}
        <div className="sync-panel-header">
          <h2>Offline Sync</h2>
          <button className="sync-panel-close" onClick={onClose}>
            &times;
          </button>
        </div>

        {/* Status Bar */}
        <div className="sync-status-bar">
          <div className="sync-status-indicator">
            <span className={`sync-status-dot ${status.isOnline ? 'online' : 'offline'}`} />
            <span>{status.isOnline ? 'Online' : 'Offline'}</span>
          </div>
          <span className="sync-last-sync">
            Last sync: {formatTime(status.lastSync)}
          </span>
        </div>

        {/* Error Display */}
        {syncError && (
          <div style={{ padding: '12px 20px', background: '#ffebee', color: '#c62828', fontSize: '14px' }}>
            {syncError}
            <button
              onClick={() => setSyncError(null)}
              style={{ float: 'right', background: 'none', border: 'none', cursor: 'pointer' }}
            >
              &times;
            </button>
          </div>
        )}

        {/* Content */}
        <div className="sync-panel-content">
          {/* Cached Issuers Section */}
          <div className="sync-section">
            <div className="sync-section-header">
              <h3>Cached Issuers ({issuers.length})</h3>
            </div>

            {issuers.length > 0 ? (
              <div className="issuer-list">
                {issuers.map((issuer) => (
                  <div key={issuer.did} className="issuer-item">
                    <div className="issuer-did">{issuer.did}</div>
                    <div className="issuer-meta">
                      <span className="issuer-key-type">{issuer.keyType}</span>
                      <span>{formatTime(issuer.cachedAt)}</span>
                      <div className="issuer-actions">
                        <button
                          className="issuer-action-btn"
                          onClick={() => handleRefreshIssuer(issuer.did)}
                          disabled={!status.isOnline || isSyncing}
                          title="Refresh"
                        >
                          🔄
                        </button>
                        <button
                          className="issuer-action-btn delete"
                          onClick={() => handleDeleteIssuer(issuer.did)}
                          title="Remove"
                        >
                          🗑️
                        </button>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            ) : (
              <div className="empty-state">
                <div className="empty-state-icon">📋</div>
                <div>No issuers cached yet</div>
                <div style={{ fontSize: '12px', marginTop: '4px' }}>
                  Add an issuer DID below to enable offline verification
                </div>
              </div>
            )}

            {/* Add Issuer Form */}
            <div className="add-issuer-form">
              <input
                type="text"
                className="add-issuer-input"
                placeholder="did:polygon:0x... or did:web:..."
                value={newDid}
                onChange={(e) => setNewDid(e.target.value)}
                onKeyDown={(e) => e.key === 'Enter' && handleAddIssuer()}
                disabled={!status.isOnline || isSyncing}
              />
              <button
                className="add-issuer-btn"
                onClick={handleAddIssuer}
                disabled={!status.isOnline || isSyncing || !newDid.trim()}
              >
                {isSyncing ? <span className="loading-spinner" /> : '+ Add'}
              </button>
            </div>
          </div>

          {/* JSON-LD Contexts Section */}
          <div className="sync-section">
            <div className="sync-section-header">
              <h3>JSON-LD Contexts ({status.contextCount})</h3>
            </div>
            <div className="context-tags">
              {builtinContextUrls.map((url) => (
                <span key={url} className="context-tag">
                  <span className="check">✓</span>
                  {url.split('/').pop()}
                </span>
              ))}
            </div>
          </div>

          {/* JSON-XT Templates Section */}
          <div className="sync-section">
            <div className="sync-section-header">
              <h3>JSON-XT Templates ({templateKeys.length})</h3>
            </div>
            {templateKeys.length > 0 ? (
              <div className="template-tags">
                {templateKeys.map((key) => (
                  <span key={key} className="template-tag">
                    <span className="check">✓</span>
                    {key}
                  </span>
                ))}
              </div>
            ) : (
              <div className="empty-state" style={{ padding: '12px' }}>
                No templates cached. Sync while online to cache templates.
              </div>
            )}
          </div>
        </div>

        {/* Footer */}
        <div className="sync-panel-footer">
          <div className="sync-footer-actions">
            <button
              className="sync-all-btn"
              onClick={handleSyncAll}
              disabled={!status.isOnline || isSyncing}
            >
              {isSyncing ? (
                <>
                  <span className="loading-spinner" />
                  Syncing...
                </>
              ) : (
                <>🔄 Sync All</>
              )}
            </button>
            <button
              className="clear-all-btn"
              onClick={handleClearAll}
              disabled={isSyncing}
            >
              🗑️ Clear All
            </button>
          </div>
          <div className="storage-indicator">
            <div className="storage-bar">
              <div
                className="storage-bar-fill"
                style={{ width: `${Math.min((status.storageUsed / (5 * 1024 * 1024)) * 100, 100)}%` }}
              />
            </div>
            <span className="storage-text">
              {formatBytes(status.storageUsed)} / 5 MB
            </span>
          </div>
        </div>
      </div>
    </>
  );
};

export default OfflineSyncPanel;
