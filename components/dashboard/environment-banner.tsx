"use client";

import { useAuth } from "@/contexts/auth-context";
import {
  bannerMessage,
  bannerVisible,
  envMismatch,
  parseAppEnv,
  primaryEnvForCopy,
} from "@/lib/env-banner";

export function EnvironmentBanner() {
  const { user } = useAuth();
  const publicEnv = parseAppEnv(process.env.NEXT_PUBLIC_APP_ENV);
  const apiEnv = user?.app_env != null ? parseAppEnv(user.app_env) : null;

  if (!bannerVisible(publicEnv, apiEnv)) {
    return null;
  }

  const primary = primaryEnvForCopy(publicEnv, apiEnv);
  const mismatch = envMismatch(publicEnv, apiEnv);
  const body = bannerMessage(primary) || bannerMessage(publicEnv) || bannerMessage(apiEnv ?? "dev");

  return (
    <div
      role="status"
      className={
        mismatch
          ? "border-b border-amber-500/80 bg-amber-500/10 px-5 py-2.5 text-sm text-amber-950 dark:border-amber-400/60 dark:bg-amber-500/15 dark:text-amber-50"
          : "border-b border-amber-400/60 bg-amber-400/10 px-5 py-2.5 text-sm text-amber-950 dark:border-amber-500/40 dark:bg-amber-400/10 dark:text-amber-50"
      }
    >
      <p className="font-medium">{body}</p>
      {mismatch ? (
        <p className="mt-1 text-xs opacity-90">
          Frontend and API environment flags do not match (NEXT_PUBLIC_APP_ENV={publicEnv},
          API app_env={apiEnv ?? "unknown"}) — check deployment configuration.
        </p>
      ) : null}
    </div>
  );
}
