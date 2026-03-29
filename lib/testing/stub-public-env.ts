import { vi } from "vitest";

/**
 * Vercel and other CI hosts inject `NEXT_PUBLIC_*` during the build. Calling
 * `vi.unstubAllEnvs()` restores those real values — it does **not** simulate a
 * clean local machine. For tests that assert default URLs when a var is
 * “unset”, stub with `undefined` instead.
 */
export function stubNextPublicApiUrlUnset(): void {
  vi.stubEnv("NEXT_PUBLIC_API_URL", undefined);
}

/** Same pitfall as {@link stubNextPublicApiUrlUnset}; auth URLs also read `NEXT_PUBLIC_APP_URL`. */
export function stubNextPublicAuthDefaultsUnset(): void {
  vi.stubEnv("NEXT_PUBLIC_API_URL", undefined);
  vi.stubEnv("NEXT_PUBLIC_APP_URL", undefined);
}
