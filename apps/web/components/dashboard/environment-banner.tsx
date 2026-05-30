"use client";

import { useAuth } from "@/contexts/auth-context";
import {
  bannerMessage,
  bannerClasses,
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
    <div role="status" className={bannerClasses(primary, mismatch)}>
      <p className="font-medium">{body}</p>
      {mismatch ? (
        <p className="mt-1 text-xs opacity-90">
          Frontend and API Environment Flags Do Not Match (NEXT_PUBLIC_APP_ENV={publicEnv},
          API app_env={apiEnv ?? "unknown"}) — Check Deployment Configuration.
        </p>
      ) : null}
    </div>
  );
}
