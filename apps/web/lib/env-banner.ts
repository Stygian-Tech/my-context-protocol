import type { AppEnv } from "./types";
import { GLASS_CHROME_BACKDROP_BLUR_CLASSES } from "./glass";
import { cn } from "./utils";

export function parseAppEnv(raw: string | undefined | null): AppEnv {
  const v = raw?.trim().toLowerCase();
  if (v === "local" || v === "dev" || v === "prod") return v;
  return "prod";
}

export function isNonProd(env: AppEnv): boolean {
  return env === "local" || env === "dev";
}

/** Show banner if client or API indicates non-production. */
export function bannerVisible(publicEnv: AppEnv, apiEnv: AppEnv | null): boolean {
  if (isNonProd(publicEnv)) return true;
  if (apiEnv != null && isNonProd(apiEnv)) return true;
  return false;
}

/** True when both are known and differ (misconfigured deploy). */
export function envMismatch(publicEnv: AppEnv, apiEnv: AppEnv | null): boolean {
  if (apiEnv == null) return false;
  return publicEnv !== apiEnv;
}

export function bannerMessage(env: AppEnv): string {
  switch (env) {
    case "local":
      return "Local Environment — Development Data and Relaxed Limits.";
    case "dev":
      return "Development Server — Not Production; Data May Be Reset.";
    case "prod":
      return "";
  }
}

export function bannerClasses(env: AppEnv, mismatch: boolean): string {
  const base = cn(
    "border-b px-5 py-2.5 text-sm",
    GLASS_CHROME_BACKDROP_BLUR_CLASSES
  );

  if (mismatch) {
    return cn(
      base,
      "border-amber-500/80 bg-amber-500/20 text-amber-950 supports-backdrop-filter:bg-amber-500/16 dark:border-amber-400/60 dark:bg-amber-500/24 dark:text-amber-50 dark:supports-backdrop-filter:bg-amber-500/20"
    );
  }

  switch (env) {
    case "local":
      return cn(
        base,
        "border-yellow-500/75 bg-yellow-400/40 text-yellow-950 shadow-sm supports-backdrop-filter:bg-yellow-400/28 dark:border-yellow-400/50 dark:bg-yellow-500/28 dark:text-yellow-50 dark:supports-backdrop-filter:bg-yellow-500/22"
      );
    case "dev":
      return cn(
        base,
        "border-red-500/70 bg-red-500/28 text-red-950 shadow-sm supports-backdrop-filter:bg-red-500/20 dark:border-red-400/45 dark:bg-red-500/24 dark:text-red-50 dark:supports-backdrop-filter:bg-red-500/20"
      );
    case "prod":
      return cn(
        base,
        "border-amber-400/60 bg-amber-400/16 text-amber-950 supports-backdrop-filter:bg-amber-400/12 dark:border-amber-500/40 dark:bg-amber-400/14 dark:text-amber-50 dark:supports-backdrop-filter:bg-amber-400/12"
      );
  }
}

/** Prefer API-reported env for copy when present; otherwise public build env. */
export function primaryEnvForCopy(publicEnv: AppEnv, apiEnv: AppEnv | null): AppEnv {
  if (apiEnv != null && isNonProd(apiEnv)) return apiEnv;
  if (isNonProd(publicEnv)) return publicEnv;
  return apiEnv ?? publicEnv;
}
