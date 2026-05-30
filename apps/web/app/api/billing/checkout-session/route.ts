import { NextRequest, NextResponse } from "next/server";
import { forwardBackendResponseCookies } from "@/lib/forward-backend-response-cookies";

const BACKEND_URL = process.env.NEXT_PUBLIC_API_URL || "http://localhost:8080";

/** Server-side proxy: forwards cookies like /api/auth/me (avoids rewrite edge cases for POST + session). */
export async function POST(request: NextRequest) {
  const requestUrl = new URL(request.url);
  const backendUrl = `${BACKEND_URL.replace(/\/$/, "")}/billing/checkout-session`;
  const cookie = request.headers.get("cookie") ?? "";
  const body = await request.text();

  const res = await fetch(backendUrl, {
    method: "POST",
    headers: {
      Cookie: cookie,
      "Content-Type": request.headers.get("content-type") ?? "application/json",
      Origin: request.headers.get("origin") ?? "",
      Referer: request.headers.get("referer") ?? "",
    },
    body: body.length > 0 ? body : undefined,
  });

  const nextRes = new NextResponse(await res.arrayBuffer(), {
    status: res.status,
    headers: {
      "content-type": res.headers.get("content-type") ?? "application/json",
    },
  });
  forwardBackendResponseCookies(res, nextRes, requestUrl);
  return nextRes;
}
