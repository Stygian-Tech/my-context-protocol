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

/** Prefer API-reported env for copy when present; otherwise public build env. */
export function primaryEnvForCopy(publicEnv: AppEnv, apiEnv: AppEnv | null): AppEnv {
  if (apiEnv != null && isNonProd(apiEnv)) return apiEnv;
  if (isNonProd(publicEnv)) return publicEnv;
  return apiEnv ?? publicEnv;
}
