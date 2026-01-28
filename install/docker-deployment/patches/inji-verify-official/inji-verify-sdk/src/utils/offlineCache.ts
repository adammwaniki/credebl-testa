/**
 * Offline Issuer Cache using localStorage
 *
 * Stores issuer public keys for offline credential verification.
 * Each issuer entry is ~200-300 bytes, so with 5MB localStorage
 * we can cache 15,000+ issuers.
 */

const CACHE_KEY = 'inji-verify-offline-issuers';
const TEMPLATES_KEY = 'inji-verify-jsonxt-templates';
const SETTINGS_KEY = 'inji-verify-offline-settings';

export interface CachedIssuer {
  did: string;
  publicKeyHex: string;
  keyType: 'Ed25519' | 'secp256k1' | string;
  didDocument?: object | null;
  cachedAt: number;
}

export interface OfflineSettings {
  enabled: boolean;
  lastSync: number | null;
  preferOffline: boolean;  // Use offline even when online (for testing)
}

/**
 * Issuer Cache - stores public keys in localStorage
 */
export const IssuerCache = {
  getAll(): Record<string, CachedIssuer> {
    try {
      const data = localStorage.getItem(CACHE_KEY);
      return data ? JSON.parse(data) : {};
    } catch (e) {
      console.error('[OfflineCache] Failed to read cache:', e);
      return {};
    }
  },

  get(did: string): CachedIssuer | null {
    const issuers = this.getAll();
    return issuers[did] || null;
  },

  set(did: string, publicKeyHex: string, keyType: string, didDocument?: object | null): void {
    try {
      const issuers = this.getAll();
      issuers[did] = {
        did,
        publicKeyHex,
        keyType,
        didDocument: didDocument || null,
        cachedAt: Date.now()
      };
      localStorage.setItem(CACHE_KEY, JSON.stringify(issuers));
      console.log('[OfflineCache] Cached issuer:', did);
    } catch (e) {
      console.error('[OfflineCache] Failed to save issuer:', e);
    }
  },

  delete(did: string): void {
    try {
      const issuers = this.getAll();
      delete issuers[did];
      localStorage.setItem(CACHE_KEY, JSON.stringify(issuers));
      console.log('[OfflineCache] Deleted issuer:', did);
    } catch (e) {
      console.error('[OfflineCache] Failed to delete issuer:', e);
    }
  },

  clear(): void {
    localStorage.removeItem(CACHE_KEY);
    console.log('[OfflineCache] Cache cleared');
  },

  count(): number {
    return Object.keys(this.getAll()).length;
  },

  list(): CachedIssuer[] {
    return Object.values(this.getAll());
  }
};

/**
 * JSON-XT Templates Cache
 */
export const TemplateCache = {
  get(): object | null {
    try {
      const data = localStorage.getItem(TEMPLATES_KEY);
      return data ? JSON.parse(data) : null;
    } catch (e) {
      console.error('[OfflineCache] Failed to read templates:', e);
      return null;
    }
  },

  set(templates: object): void {
    try {
      localStorage.setItem(TEMPLATES_KEY, JSON.stringify(templates));
      console.log('[OfflineCache] Templates cached');
    } catch (e) {
      console.error('[OfflineCache] Failed to save templates:', e);
    }
  },

  clear(): void {
    localStorage.removeItem(TEMPLATES_KEY);
  }
};

/**
 * Offline Settings
 */
export const OfflineSettingsStore = {
  get(): OfflineSettings {
    try {
      const data = localStorage.getItem(SETTINGS_KEY);
      return data ? JSON.parse(data) : {
        enabled: true,
        lastSync: null,
        preferOffline: false
      };
    } catch (e) {
      return { enabled: true, lastSync: null, preferOffline: false };
    }
  },

  set(settings: Partial<OfflineSettings>): void {
    try {
      const current = this.get();
      const updated = { ...current, ...settings };
      localStorage.setItem(SETTINGS_KEY, JSON.stringify(updated));
    } catch (e) {
      console.error('[OfflineCache] Failed to save settings:', e);
    }
  },

  setLastSync(): void {
    this.set({ lastSync: Date.now() });
  }
};

/**
 * Sync issuer from adapter while online
 */
export async function syncIssuer(did: string, adapterUrl: string): Promise<boolean> {
  try {
    const response = await fetch(`${adapterUrl}/sync`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ did })
    });

    if (!response.ok) {
      throw new Error(`Sync failed: ${response.status}`);
    }

    const result = await response.json();

    if (result.results?.[0]?.success) {
      const r = result.results[0];
      // The adapter returns truncated publicKeyHex, we need full key
      // For now, store what we have - the adapter handles verification
      IssuerCache.set(did, r.publicKeyHex || '', r.keyType || 'unknown');
      OfflineSettingsStore.setLastSync();
      return true;
    }

    console.error('[OfflineCache] Sync failed:', result);
    return false;
  } catch (e) {
    console.error('[OfflineCache] Sync error:', e);
    return false;
  }
}

/**
 * Sync JSON-XT templates from adapter
 */
export async function syncTemplates(adapterUrl: string): Promise<boolean> {
  try {
    // Try to fetch templates from adapter
    const response = await fetch(`${adapterUrl}/templates`);
    if (response.ok) {
      const templates = await response.json();
      TemplateCache.set(templates);
      return true;
    }
    return false;
  } catch (e) {
    console.error('[OfflineCache] Template sync error:', e);
    return false;
  }
}

/**
 * Check if we're online
 */
export function isOnline(): boolean {
  return navigator.onLine;
}

/**
 * Check if offline mode should be used
 */
export function shouldUseOffline(): boolean {
  const settings = OfflineSettingsStore.get();
  if (!settings.enabled) return false;
  if (settings.preferOffline) return true;
  return !isOnline();
}
