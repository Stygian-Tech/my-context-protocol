import type { AppEnv } from "./types";

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
  const base =
    "sticky top-0 z-50 border-b px-5 py-2.5 text-sm supports-backdrop-filter:backdrop-blur-sm";

  if (mismatch) {
    return `${base} border-amber-500/80 bg-amber-500/20 text-amber-950 dark:border-amber-400/60 dark:bg-amber-500/24 dark:text-amber-50`;
  }

  switch (env) {
    case "local":
      return `${base} border-yellow-500/75 bg-yellow-400/40 text-yellow-950 shadow-sm dark:border-yellow-400/50 dark:bg-yellow-500/28 dark:text-yellow-50`;
    case "dev":
      return `${base} border-red-500/70 bg-red-500/28 text-red-950 shadow-sm dark:border-red-400/45 dark:bg-red-500/24 dark:text-red-50`;
    case "prod":
      return `${base} border-amber-400/60 bg-amber-400/16 text-amber-950 dark:border-amber-500/40 dark:bg-amber-400/14 dark:text-amber-50`;
  }
}

/** Prefer API-reported env for copy when present; otherwise public build env. */
export function primaryEnvForCopy(publicEnv: AppEnv, apiEnv: AppEnv | null): AppEnv {
  if (apiEnv != null && isNonProd(apiEnv)) return apiEnv;
  if (isNonProd(publicEnv)) return publicEnv;
  return apiEnv ?? publicEnv;
}
