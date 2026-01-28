import React, { useState, useEffect } from 'react';
import { useTranslation } from 'react-i18next';

interface CachedIssuer {
  did: string;
  publicKeyHex: string;
  keyType: string;
  cachedAt: number;
}

const CACHE_KEY = 'inji-verify-offline-issuers';

// Simple cache functions (matching SDK implementation)
const IssuerCache = {
  getAll(): Record<string, CachedIssuer> {
    try {
      const data = localStorage.getItem(CACHE_KEY);
      return data ? JSON.parse(data) : {};
    } catch (e) {
      return {};
    }
  },

  set(did: string, publicKeyHex: string, keyType: string): void {
    try {
      const issuers = this.getAll();
      issuers[did] = {
        did,
        publicKeyHex,
        keyType,
        cachedAt: Date.now()
      };
      localStorage.setItem(CACHE_KEY, JSON.stringify(issuers));
    } catch (e) {
      console.error('Failed to save issuer:', e);
    }
  },

  delete(did: string): void {
    try {
      const issuers = this.getAll();
      delete issuers[did];
      localStorage.setItem(CACHE_KEY, JSON.stringify(issuers));
    } catch (e) {
      console.error('Failed to delete issuer:', e);
    }
  },

  count(): number {
    return Object.keys(this.getAll()).length;
  },

  list(): CachedIssuer[] {
    return Object.values(this.getAll());
  }
};

const OfflineSyncPanel: React.FC = () => {
  const [isOpen, setIsOpen] = useState(false);
  const [isOnline, setIsOnline] = useState(navigator.onLine);
  const [issuers, setIssuers] = useState<CachedIssuer[]>([]);
  const [newDid, setNewDid] = useState('');
  const [syncing, setSyncing] = useState(false);
  const [syncError, setSyncError] = useState<string | null>(null);
  const [syncSuccess, setSyncSuccess] = useState<string | null>(null);

  // Update online status
  useEffect(() => {
    const handleOnline = () => setIsOnline(true);
    const handleOffline = () => setIsOnline(false);

    window.addEventListener('online', handleOnline);
    window.addEventListener('offline', handleOffline);

    return () => {
      window.removeEventListener('online', handleOnline);
      window.removeEventListener('offline', handleOffline);
    };
  }, []);

  // Load cached issuers
  useEffect(() => {
    if (isOpen) {
      setIssuers(IssuerCache.list());
    }
  }, [isOpen]);

  const refreshIssuers = () => {
    setIssuers(IssuerCache.list());
  };

  const syncIssuer = async () => {
    if (!newDid.trim()) return;

    setSyncing(true);
    setSyncError(null);
    setSyncSuccess(null);

    try {
      // The adapter runs on port 8085, try multiple URLs
      const baseUrl = window.location.origin;
      const adapterPort = '8085';
      const adapterHost = window.location.hostname;

      // Try URLs in order: same-origin proxy, then direct adapter port
      const urlsToTry = [
        `${baseUrl}/sync`,  // If nginx proxies /sync to adapter
        `http://${adapterHost}:${adapterPort}/sync`,  // Direct adapter port
      ];

      let lastError = null;
      let success = false;
      let result = null;

      for (const syncUrl of urlsToTry) {
        try {
          console.log('Trying sync via:', syncUrl);

          const response = await fetch(syncUrl, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ did: newDid.trim() })
          });

          if (!response.ok) {
            throw new Error(`Sync failed: ${response.status}`);
          }

          result = await response.json();
          success = true;
          break;  // Success, exit loop
        } catch (e) {
          lastError = e;
          console.log('Sync attempt failed:', e);
          // Continue to next URL
        }
      }

      if (!success) {
        throw lastError || new Error('All sync attempts failed');
      }

      if (result?.results?.[0]?.success) {
        const r = result.results[0];
        IssuerCache.set(newDid.trim(), r.publicKeyHex || '', r.keyType || 'unknown');
        setSyncSuccess(`Synced: ${newDid.substring(0, 30)}...`);
        setNewDid('');
        refreshIssuers();
      } else {
        throw new Error(result?.results?.[0]?.error || 'Sync failed');
      }
    } catch (e) {
      setSyncError(e instanceof Error ? e.message : 'Sync failed');
    } finally {
      setSyncing(false);
    }
  };

  const deleteIssuer = (did: string) => {
    IssuerCache.delete(did);
    refreshIssuers();
  };

  const formatDate = (timestamp: number) => {
    return new Date(timestamp).toLocaleString();
  };

  const truncateDid = (did: string) => {
    if (did.length <= 40) return did;
    return did.substring(0, 20) + '...' + did.substring(did.length - 15);
  };

  return (
    <>
      {/* Floating button */}
      <button
        onClick={() => setIsOpen(!isOpen)}
        className={`fixed bottom-4 right-4 z-[9999] p-3 rounded-full shadow-lg transition-all ${
          isOnline ? 'bg-green-500 hover:bg-green-600' : 'bg-orange-500 hover:bg-orange-600'
        } text-white`}
        title={isOnline ? 'Online - Click to manage offline cache' : 'Offline - Click to view cached issuers'}
      >
        <svg xmlns="http://www.w3.org/2000/svg" className="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          {isOnline ? (
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8.111 16.404a5.5 5.5 0 017.778 0M12 20h.01m-7.08-7.071c3.904-3.905 10.236-3.905 14.14 0M1.394 9.393c5.857-5.857 15.355-5.857 21.213 0" />
          ) : (
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M18.364 5.636a9 9 0 010 12.728m0 0l-2.829-2.829m2.829 2.829L21 21M15.536 8.464a5 5 0 010 7.072m0 0l-2.829-2.829m-4.243 2.829a4.978 4.978 0 01-1.414-2.83m-1.414 5.658a9 9 0 01-2.167-9.238m7.824 2.167a1 1 0 111.414 1.414m-1.414-1.414L3 3" />
          )}
        </svg>
        {IssuerCache.count() > 0 && (
          <span className="absolute -top-1 -right-1 bg-blue-600 text-white text-xs rounded-full h-5 w-5 flex items-center justify-center">
            {IssuerCache.count()}
          </span>
        )}
      </button>

      {/* Panel */}
      {isOpen && (
        <div className="fixed bottom-20 right-4 z-[9999] w-80 max-h-[70vh] bg-white rounded-lg shadow-xl border overflow-hidden">
          {/* Header */}
          <div className={`p-3 ${isOnline ? 'bg-green-500' : 'bg-orange-500'} text-white`}>
            <div className="flex justify-between items-center">
              <h3 className="font-bold">Offline Verification</h3>
              <button onClick={() => setIsOpen(false)} className="text-white hover:text-gray-200">
                <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
                  <path fillRule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clipRule="evenodd" />
                </svg>
              </button>
            </div>
            <p className="text-sm opacity-90">
              {isOnline ? 'Online - Sync issuers for offline use' : 'Offline - Using cached issuers'}
            </p>
          </div>

          {/* Content */}
          <div className="p-3 overflow-y-auto max-h-[50vh]">
            {/* Sync form (only when online) */}
            {isOnline && (
              <div className="mb-4">
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Sync Issuer DID
                </label>
                <div className="flex gap-2">
                  <input
                    type="text"
                    value={newDid}
                    onChange={(e) => setNewDid(e.target.value)}
                    placeholder="did:polygon:testnet:0x..."
                    className="flex-1 p-2 text-sm border rounded focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                    disabled={syncing}
                  />
                  <button
                    onClick={syncIssuer}
                    disabled={syncing || !newDid.trim()}
                    className="px-3 py-2 bg-blue-500 text-white text-sm rounded hover:bg-blue-600 disabled:bg-gray-300 disabled:cursor-not-allowed"
                  >
                    {syncing ? '...' : 'Sync'}
                  </button>
                </div>
                {syncError && (
                  <p className="mt-1 text-sm text-red-600">{syncError}</p>
                )}
                {syncSuccess && (
                  <p className="mt-1 text-sm text-green-600">{syncSuccess}</p>
                )}
              </div>
            )}

            {/* Cached issuers list */}
            <div>
              <h4 className="text-sm font-medium text-gray-700 mb-2">
                Cached Issuers ({issuers.length})
              </h4>
              {issuers.length === 0 ? (
                <p className="text-sm text-gray-500 italic">
                  No issuers cached. {isOnline ? 'Sync an issuer above.' : 'Connect to internet to sync.'}
                </p>
              ) : (
                <ul className="space-y-2">
                  {issuers.map((issuer) => (
                    <li key={issuer.did} className="p-2 bg-gray-50 rounded text-xs">
                      <div className="flex justify-between items-start">
                        <div className="flex-1 overflow-hidden">
                          <p className="font-mono truncate" title={issuer.did}>
                            {truncateDid(issuer.did)}
                          </p>
                          <p className="text-gray-500">
                            {issuer.keyType} | {formatDate(issuer.cachedAt)}
                          </p>
                        </div>
                        <button
                          onClick={() => deleteIssuer(issuer.did)}
                          className="ml-2 text-red-500 hover:text-red-700"
                          title="Remove from cache"
                        >
                          <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                            <path fillRule="evenodd" d="M9 2a1 1 0 00-.894.553L7.382 4H4a1 1 0 000 2v10a2 2 0 002 2h8a2 2 0 002-2V6a1 1 0 100-2h-3.382l-.724-1.447A1 1 0 0011 2H9zM7 8a1 1 0 012 0v6a1 1 0 11-2 0V8zm5-1a1 1 0 00-1 1v6a1 1 0 102 0V8a1 1 0 00-1-1z" clipRule="evenodd" />
                          </svg>
                        </button>
                      </div>
                    </li>
                  ))}
                </ul>
              )}
            </div>
          </div>

          {/* Footer */}
          <div className="p-2 bg-gray-50 border-t text-xs text-gray-500 text-center">
            {isOnline
              ? 'Sync issuers while online to verify offline later'
              : 'Verification will use cached issuer keys'
            }
          </div>
        </div>
      )}
    </>
  );
};

export default OfflineSyncPanel;
