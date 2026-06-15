import { isNonProd, parseAppEnv } from "@/lib/env-banner";

const ERROR_BODY_MAX_CHARS = 1200;

/**
 * Browser + SSR API fetch tracing for non-production (max detail: timings, non-OK bodies truncated).
 * Set `NEXT_PUBLIC_CLIENT_API_LOG=0` to disable. Production: `NEXT_PUBLIC_CLIENT_API_LOG=1` to opt in.
 *
 * Disabled when `NODE_ENV === "test"` unless `NEXT_PUBLIC_CLIENT_API_LOG=1`.
 */
export function isClientApiLoggingEnabled(): boolean {
  const raw = process.env.NEXT_PUBLIC_CLIENT_API_LOG?.trim() ?? "";
  if (raw.length > 0) {
    const v = raw.toLowerCase();
    if (v === "0" || v === "false" || v === "no") return false;
    if (v === "1" || v === "true" || v === "yes") return true;
  }

  if (process.env.NODE_ENV === "test") {
    return false;
  }

  const vercel = process.env.VERCEL_ENV;
  if (vercel === "preview" || vercel === "development") {
    return true;
  }

  if (process.env.NODE_ENV === "development") {
    return true;
  }

  return isNonProd(parseAppEnv(process.env.NEXT_PUBLIC_APP_ENV));
}

function bodyHint(body: RequestInit["body"]): string {
  if (body == null || body === undefined) {
    return "";
  }
  if (typeof body === "string") {
    return ` bodyLen=${body.length}`;
  }
  return " body=<non-string>";
}

/** Uses `console.info` for outbound/success so default DevTools levels show traces without “Verbose”. */
export function logClientApiRequest(
  method: string,
  url: string,
  options: Pick<RequestInit, "body">
): void {
  if (!isClientApiLoggingEnabled()) {
    return;
  }
  const hint = bodyHint(options.body);
  console.info(`[client-api] → ${method} ${url}${hint}`);
}

export function logClientApiResponse(
  method: string,
  url: string,
  status: number,
  durationMs: number,
  ok: boolean
): void {
  if (!isClientApiLoggingEnabled()) {
    return;
  }
  const line = `[client-api] ← ${method} ${url} status=${status} durationMs=${durationMs}`;
  if (ok && status < 400) {
    console.info(line);
  } else {
    console.warn(line);
  }
}

export function logClientApiError(method: string, url: string, durationMs: number, err: unknown): void {
  if (!isClientApiLoggingEnabled()) {
    return;
  }
  const msg = err instanceof Error ? err.message : String(err);
  console.warn(`[client-api] ✕ ${method} ${url} durationMs=${durationMs} error=${msg}`);
}

/** Logs a truncated API error payload after a non-OK HTTP status (no secrets redaction — dev only). */
export function logClientApiErrorBody(body: unknown): void {
  if (!isClientApiLoggingEnabled()) {
    return;
  }
  if (body === undefined || body === null) {
    return;
  }
  try {
    const text = typeof body === "string" ? body : JSON.stringify(body);
    const clipped = text.length > ERROR_BODY_MAX_CHARS ? `${text.slice(0, ERROR_BODY_MAX_CHARS)}…` : text;
    console.warn(`[client-api] error body: ${clipped}`);
  } catch {
    console.warn("[client-api] error body: <could not stringify>");
  }
}
