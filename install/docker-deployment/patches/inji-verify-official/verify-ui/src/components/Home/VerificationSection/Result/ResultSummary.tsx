import React from "react";
import { VerificationSuccessIcon, VerificationFailedIcon } from "../../../../utils/theme-utils";
import { useTranslation } from "react-i18next";

const backgroundColorMapping: any = {
  SUCCESS: "bg-successText",
  EXPIRED: "bg-expiredText",
  INVALID: "bg-invalidText",
  REVOKED: "bg-revokedText",
  UNKNOWN_ISSUER: "bg-expiredText",
  ERROR: "bg-invalidText",
};

interface ResultSummaryProps {
  status: "SUCCESS" | "EXPIRED" | "INVALID" | "TIMEOUT" | "REVOKED" | "UNKNOWN_ISSUER" | "ERROR";
  offline?: boolean;
  verificationLevel?: 'CRYPTOGRAPHIC' | 'TRUSTED_ISSUER';
  message?: string;
}

const ResultSummary = ({
  status,
  offline,
  verificationLevel,
  message,
}: ResultSummaryProps) => {
  const bgColor = backgroundColorMapping[status] || "bg-invalidText";
  const { t } = useTranslation("ResultSummary");
  return (
    <div
      className={`flex flex-col items-center justify-center h-[170px] lg:h-[186px] ${bgColor}`}
    >
      <div className={`block mb-2.5 text-white`}>
        {status === "SUCCESS" ? (
          <VerificationSuccessIcon id="success_message_icon" />
        ) : (
          <VerificationFailedIcon />
        )}
      </div>
      <div className={`rounded-xl p-1`}>
        <p
          id="vc-result-display-message"
          className={`font-normal text-normalTextSize lg:text-lgNormalTextSize text-center text-white`}
        >
          {t(`${status}`)}
        </p>
        {offline && (
          <p className="text-xs text-center text-white/80 mt-1">
            {verificationLevel === 'TRUSTED_ISSUER'
              ? '⚡ Verified offline (trusted issuer)'
              : '⚡ Verified offline'}
          </p>
        )}
        {message && (
          <p className="text-xs text-center text-white/70 mt-1">
            {message}
          </p>
        )}
      </div>
    </div>
  );
};

export default ResultSummary;
