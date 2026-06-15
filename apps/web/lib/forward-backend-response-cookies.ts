import type { NextResponse } from "next/server";

/**
 * Copies Set-Cookie from a backend fetch response onto a NextResponse for the app origin.
 * Strips `Domain=` so the browser stores the cookie on the frontend host (see auth/confirm).
 */
export function forwardBackendResponseCookies(
  backendRes: Response,
  nextRes: NextResponse,
  requestUrl: URL
): void {
  const isInsecureContext = requestUrl.protocol === "http:";
  const resHeaders = backendRes.headers as Headers & {
    getSetCookie?: () => string[];
  };
  const setCookies =
    resHeaders.getSetCookie?.() ?? backendRes.headers.get("set-cookie");
  if (!setCookies) {
    return;
  }
  const cookies = Array.isArray(setCookies) ? setCookies : [setCookies];
  for (const c of cookies) {
    let rewritten = c.replace(/;\s*Domain=[^;]+/gi, "").replace(/;\s*$/g, "");
    if (isInsecureContext) {
      rewritten = rewritten.replace(/;\s*Secure\b/gi, "");
    }
    if (!rewritten.includes("SameSite=")) {
      rewritten += "; SameSite=Lax";
    }
    nextRes.headers.append("Set-Cookie", rewritten);
  }
}
