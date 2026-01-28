import {
  AppError,
  PresentationDefinition,
  VPRequestBody,
} from "../components/openid4vp-verification/OpenID4VPVerification.types";
import {
  vcSubmissionBody
} from "../components/qrcode-verification/QRCodeVerification.types";
import {QrData} from "../types/OVPSchemeQrData";
import { verifyOffline, canVerifyOffline } from "./offlineVerifier";
import { shouldUseOffline, IssuerCache } from "./offlineCache";

const generateNonce = (): string => {
  return btoa(Date.now().toString());
};

/**
 * Verify credential - with offline fallback
 *
 * Tries online verification first, falls back to offline if:
 * 1. Network is unavailable
 * 2. Server request fails
 * 3. User has enabled "prefer offline" mode
 */
export const vcVerification = async (credential: unknown, url: string) => {
  // Check if we should use offline mode
  const useOffline = shouldUseOffline();
  const credentialString = typeof credential === "string" ? credential : JSON.stringify(credential);

  // If offline mode is preferred or we're offline, try offline verification first
  if (useOffline && canVerifyOffline(credentialString)) {
    console.log("[vcVerification] Using offline verification");
    try {
      const offlineResult = await verifyOffline(credentialString);
      return {
        verificationStatus: offlineResult.status,
        vc: offlineResult.credential,
        offline: true,
        verificationLevel: offlineResult.verificationLevel,
        message: offlineResult.message
      };
    } catch (offlineError) {
      console.error("[vcVerification] Offline verification failed:", offlineError);
      // If we're truly offline, throw the error
      if (!navigator.onLine) {
        throw offlineError;
      }
      // Otherwise, fall through to online verification
    }
  }

  // Online verification
  let body: string;
  let contentType: string;
  if (typeof credential === "string") {
    body = credential;
    // Check if it's a JSON-XT URI (jxt:resolver:type:version:data)
    if (credential.startsWith("jxt:")) {
      contentType = "text/plain";  // JSON-XT URI - adapter will decode
    } else {
      contentType = "application/vc+sd-jwt";
    }
  } else {
    body = JSON.stringify(credential);
    contentType = "application/vc+ld+json";
  }
  const requestOptions = {
    method: "POST",
    headers: {
      "Content-Type": contentType,
    },
    body: body,
  };

  try {
    const response = await fetch(url + "/vc-verification", requestOptions);
    const data = await response.json();
    if (response.status !== 200) throw new Error(`Failed VC Verification due to: ${ data.error || "Unknown Error" }`);

    // Cache the issuer for future offline use
    if (data.vc || data.verifiableCredential) {
      const vc = data.vc || data.verifiableCredential;
      const issuerDid = typeof vc.issuer === "string" ? vc.issuer : vc.issuer?.id;
      if (issuerDid && !IssuerCache.get(issuerDid)) {
        // Note: We don't have the public key here, but we mark the issuer as "seen"
        // A full sync should be done via the /sync endpoint
        console.log("[vcVerification] Issuer verified online:", issuerDid);
      }
    }

    // For JSON-XT credentials, return full response so UI can display credential details
    if (data.vc || data.verifiableCredential) {
      return {
        verificationStatus: data.verificationStatus,
        vc: data.vc || data.verifiableCredential,
        offline: false
      };
    }
    return data.verificationStatus;
  } catch (error) {
    console.error("[vcVerification] Online verification failed:", error);

    // Fallback to offline verification if network failed
    if (canVerifyOffline(credentialString)) {
      console.log("[vcVerification] Falling back to offline verification");
      try {
        const offlineResult = await verifyOffline(credentialString);
        return {
          verificationStatus: offlineResult.status,
          vc: offlineResult.credential,
          offline: true,
          verificationLevel: offlineResult.verificationLevel,
          message: offlineResult.message || "Verified offline (network unavailable)"
        };
      } catch (offlineError) {
        console.error("[vcVerification] Offline fallback also failed:", offlineError);
      }
    }

    if (error instanceof Error) {
      throw Error(error.message);
    } else {
      throw new Error("An unknown error occurred");
    }
  }
};

export const vcSubmission = async (
  credential: unknown,
  url: string,
  txnId?: string
) => {
  const requestBody: vcSubmissionBody = {
    vc: JSON.stringify(credential),
  };
  if (txnId) requestBody.transactionId = txnId;
  const requestOptions = {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify(requestBody),
  };

  try {
    const response = await fetch(url + "/vc-submission", requestOptions);
    const data = await response.json();
    if (response.status !== 200) throw new Error(`Failed to Submit VC due to: ${ data.error || "Unknown Error" }`);
    return data.transactionId;
  } catch (error) {
    console.error(error);
    if (error instanceof Error) {
      throw Error(error.message);
    } else {
      throw new Error("An unknown error occurred");
    }
  }
};

export const vpRequest = async (
  url: string,
  clientId: string,
  txnId?: string,
  presentationDefinitionId?: string,
  presentationDefinition?: PresentationDefinition
) => {
  const requestBody: VPRequestBody = {
    clientId: clientId,
    nonce: generateNonce(),
  };

  if (txnId) requestBody.transactionId = txnId;
  if (presentationDefinitionId)
    requestBody.presentationDefinitionId = presentationDefinitionId;
  if (presentationDefinition)
    requestBody.presentationDefinition = presentationDefinition;

  const requestOptions = {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify(requestBody),
  };

  try {
    const response = await fetch(url + "/vp-request", requestOptions);
    if (response.status !== 201) throw new Error("Failed to create VP request");
    const data: QrData = await response.json();
    return data;
  } catch (error) {
    console.error(error);
    if (error instanceof Error) {
      throw Error(error.message);
    } else {
      throw new Error("An unknown error occurred");
    }
  }
};

export const vpRequestStatus = async (url: string, reqId: string) => {
  try {
    const response = await fetch(url + `/vp-request/${reqId}/status`);
    if (response.status !== 200) throw new Error("Failed to fetch status");
    const data = await response.json();
    return data;
  } catch (error) {
    console.error(error);
    if (error instanceof Error) {
      throw Error(error.message);
    } else {
      throw new Error("An unknown error occurred");
    }
  }
};

const isAppError = (error: unknown): error is AppError => (
  typeof error === 'object' &&
  error !== null &&
  'errorMessage' in error &&
  typeof (error as Record<string, unknown>).errorMessage === 'string'
);

export const vpResult = async (url: string, txnId: string) => {
  try {
    const response = await fetch(url + `/vp-result/${txnId}`);
    const data = await response.json();
    if (response.status !== 200) {
      throw {
        errorCode: data.errorCode,
        errorMessage: data.errorMessage || data.error || "Unknown error",
        transactionId: txnId ?? null
      } as AppError;
    }
    return data.vcResults;
  } catch (error) {
    if (isAppError(error)) {
      throw error as AppError;
    } else {
      throw error;
    }
  }
};