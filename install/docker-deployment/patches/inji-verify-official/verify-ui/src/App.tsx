import React, { useEffect, useRef } from "react";
import "./App.css";
import Home from "./pages/Home";
import Offline from "./pages/Offline";
import { Scan } from "./pages/Scan";
import { RouterProvider, createBrowserRouter } from "react-router-dom";
import AlertMessage from "./components/commons/AlertMessage";
import PreloadImages from "./components/commons/PreloadImages";
import PageNotFound404 from "./pages/PageNotFound404";
import { Pages } from "./utils/config";
import { useAppSelector } from "./redux/hooks";
import store, { RootState } from "./redux/store";
import { isRTL } from "./utils/i18n";
import { VerificationMethod } from "./types/data-types";
import { goToHomeScreen } from "./redux/features/verification/verification.slice";
import { Verify } from "./pages/Verify";
import PageTemplate from "./components/PageTemplate";
import {
  syncTemplates,
  syncIssuer,
  OfflineSettingsStore,
  IssuerCache,
  TemplateCache
} from "@mosip/react-inji-verify-sdk";

function switchToVerificationMethod(method: VerificationMethod) {
  const sessionStoragePath = sessionStorage.getItem('pathName');
  let methodPath = "";
  switch (method) {
    case "UPLOAD":
      methodPath = Pages.Home;
      break;
    case "SCAN":
      methodPath = Pages.Scan;
      break;
    case "VERIFY":
      methodPath = Pages.VerifyCredentials;
      break;
    default:
      methodPath = Pages.Home;
  }
  if (sessionStoragePath && sessionStoragePath !== methodPath) {
    sessionStorage.removeItem("pathName");
    sessionStorage.removeItem("transactionId");
    sessionStorage.removeItem("requestId");
  }
  store.dispatch(goToHomeScreen({ method }));
  return null;
}

const router = createBrowserRouter([
  {
    path: "/",
    element: <PageTemplate />,
    children: [
      {
        path: Pages.Home,
        element: <Home/>,
        loader: () => switchToVerificationMethod("UPLOAD"),
      },
      {
        path: Pages.Scan,
        element: <Scan/>,
        loader: () => switchToVerificationMethod("SCAN"),
      },
      {
        path: Pages.VerifyCredentials,
        element: <Verify/>,
        loader: () => switchToVerificationMethod("VERIFY"),
      },
      {
        path: Pages.Offline,
        element: <Offline/>,
      },
      {
        path: Pages.PageNotFound,
        element: <PageNotFound404/>,
      },
    ]
  }
]);

// Known issuers to pre-cache for offline verification
const KNOWN_ISSUERS = [
  'did:polygon:0xD3A288e4cCeb5ADE57c5B674475d6728Af3bD9Fd', // CREDEBL Polygon issuer
  'did:web:mosip.github.io:inji-config:collab:tan',          // MOSIP Collab issuer
];

function App() {
  const language = useAppSelector((state: RootState) => state.common.language);
  const rtl = isRTL(language);
  const preloadImages = ['/assets/images/under_construction.svg', '/assets/images/inji-logo.svg'];
  const syncAttemptedRef = useRef(false);

  // Auto-sync offline caches when online
  useEffect(() => {
    const autoSyncOfflineData = async () => {
      // Only sync once per session and only when online
      if (syncAttemptedRef.current || !navigator.onLine) return;
      syncAttemptedRef.current = true;

      const verifyServiceUrl = window.location.origin + (window._env_?.VERIFY_SERVICE_API_URL || '/v1/verify');
      console.log('[App] Auto-syncing offline data from:', verifyServiceUrl);

      try {
        // Sync JSON-XT templates if not already cached
        if (!TemplateCache.get()) {
          console.log('[App] Syncing JSON-XT templates...');
          const templatesOk = await syncTemplates(verifyServiceUrl);
          if (templatesOk) {
            console.log('[App] JSON-XT templates synced successfully');
          } else {
            console.warn('[App] JSON-XT templates sync failed (adapter may not have templates endpoint)');
          }
        } else {
          console.log('[App] JSON-XT templates already cached');
        }

        // Sync known issuers if not already cached
        for (const did of KNOWN_ISSUERS) {
          if (!IssuerCache.get(did)) {
            console.log('[App] Syncing issuer:', did);
            try {
              await syncIssuer(did, verifyServiceUrl);
            } catch (e) {
              console.warn('[App] Failed to sync issuer:', did, e);
            }
          }
        }

        // Update last sync time
        OfflineSettingsStore.setLastSync();
        console.log('[App] Offline data sync complete. Cached issuers:', IssuerCache.count());
      } catch (e) {
        console.error('[App] Auto-sync failed:', e);
      }
    };

    // Run sync after a short delay to not block initial render
    const timeoutId = setTimeout(autoSyncOfflineData, 1000);
    return () => clearTimeout(timeoutId);
  }, []);

  useEffect(() => {
    document.body.classList.toggle('rtl', rtl);
    document.documentElement.classList.add('default_theme');
  }, [rtl]);

  return (
    <div className="font-base">
      <RouterProvider router={router}/>
      <AlertMessage isRtl={rtl}/>
      <PreloadImages imageUrls={preloadImages}/>
    </div>
  );
}

export default App;
