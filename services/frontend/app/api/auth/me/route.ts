import { NextRequest, NextResponse } from "next/server";

const BACKEND_URL = process.env.NEXT_PUBLIC_API_URL || "http://localhost:8080";

/**
 * Proxy /api/auth/me to backend, forwarding the session cookie.
 * Ensures the cookie set by /api/auth/confirm is sent to the backend.
 */
export async function GET(request: NextRequest) {
  const backendUrl = `${BACKEND_URL.replace(/\/$/, "")}/auth/me`;
  const cookie = request.headers.get("cookie") || "";

  const res = await fetch(backendUrl, {
    method: "GET",
    headers: { Cookie: cookie },
  });

  if (!res.ok) {
    return NextResponse.json(
      { error: res.statusText },
      { status: res.status }
    );
  }

  const data = await res.json();
  return NextResponse.json(data);
}
