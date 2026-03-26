import { NextRequest, NextResponse } from "next/server";
import { assertSafeRelativeRedirectPath } from "@/lib/safe-redirect";

const BACKEND_URL = process.env.NEXT_PUBLIC_API_URL || "http://localhost:8080";

export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);
  const token = searchParams.get("token");
  const redirectTo = searchParams.get("redirect");

  if (!token || redirectTo == null || redirectTo === "") {
    return NextResponse.redirect(new URL("/login?error=missing_params", request.url), 302);
  }
  try {
    assertSafeRelativeRedirectPath(redirectTo);
  } catch {
    return NextResponse.redirect(new URL("/login?error=invalid_redirect", request.url), 302);
  }

  const backendUrl = `${BACKEND_URL.replace(/\/$/, "")}/auth/confirm?token=${encodeURIComponent(token)}&redirect=${encodeURIComponent(redirectTo)}`;

  const res = await fetch(backendUrl, {
    method: "GET",
    redirect: "manual",
    headers: {
      Cookie: request.headers.get("cookie") || "",
    },
  });

  // Vapor uses 303 See Other for req.redirect(.normal); only checking 302 skipped Set-Cookie forwarding.
  const location = res.headers.get("location");
  const isBackendRedirect =
    Boolean(location) && res.status >= 300 && res.status < 400;

  if (isBackendRedirect && location) {
    const requestUrl = new URL(request.url);
    const isInsecureContext = requestUrl.protocol === "http:";
    // Use 302 to the browser even when Vapor returns 303 — avoids rare clients mishandling Set-Cookie on 303.
    const response = NextResponse.redirect(location, 302);
    const setCookies = (res.headers as Headers & { getSetCookie?: () => string[] }).getSetCookie?.() ?? res.headers.get("set-cookie");
    if (setCookies) {
      const cookies = Array.isArray(setCookies) ? setCookies : [setCookies];
      cookies.forEach((c) => {
        let rewritten = c.replace(/;\s*Domain=[^;]+/gi, "").replace(/;\s*$/g, "");
        if (isInsecureContext) {
          rewritten = rewritten.replace(/;\s*Secure\b/gi, "");
        }
        if (!rewritten.includes("SameSite=")) {
          rewritten += "; SameSite=Lax";
        }
        response.headers.append("Set-Cookie", rewritten);
      });
    }
    return response;
  }

  if (res.ok) {
    return NextResponse.json(await res.json());
  }

  // 401 = token already consumed. First request succeeded; redirect to return URL (or /) instead of auth_failed.
  if (res.status === 401) {
    try {
      assertSafeRelativeRedirectPath(redirectTo);
      return NextResponse.redirect(new URL(redirectTo, request.url), 302);
    } catch {
      /* invalid */
    }
    return NextResponse.redirect(new URL("/", request.url), 302);
  }

  return NextResponse.redirect(new URL(`/login?error=auth_failed`, request.url), 302);
}
