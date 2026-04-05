"use client";

import { useAuth } from "@/contexts/auth-context";
import {
  bannerMessage,
  bannerVisible,
  envMismatch,
  parseAppEnv,
  primaryEnvForCopy,
} from "@/lib/env-banner";
import { cn } from "@/lib/utils";

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
  const isLocal = primary === "local";
  const isDev = primary === "dev";

  return (
    <div
      role="status"
      className={cn(
        "sticky top-0 z-50",
        mismatch
          ? "border-b border-amber-500/80 bg-amber-500/10 px-5 py-2.5 text-sm text-amber-950 dark:border-amber-400/60 dark:bg-amber-500/15 dark:text-amber-50"
          : isLocal
            ? "border-b border-yellow-500/75 bg-yellow-400/25 px-5 py-2.5 text-sm text-yellow-950 shadow-sm dark:border-yellow-400/50 dark:bg-yellow-500/20 dark:text-yellow-50"
            : isDev
              ? "border-b border-red-500/70 bg-red-500/18 px-5 py-2.5 text-sm text-red-950 shadow-sm dark:border-red-400/45 dark:bg-red-500/16 dark:text-red-50"
              : "border-b border-amber-400/60 bg-amber-400/10 px-5 py-2.5 text-sm text-amber-950 dark:border-amber-500/40 dark:bg-amber-400/10 dark:text-amber-50"
      )}
    >
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
