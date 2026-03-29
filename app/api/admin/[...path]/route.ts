import { NextRequest, NextResponse } from "next/server";
import { forwardBackendResponseCookies } from "@/lib/forward-backend-response-cookies";

const BACKEND_URL = (process.env.NEXT_PUBLIC_API_URL || "http://localhost:8080").replace(
  /\/$/,
  ""
);

/** Avoid relying on next.config rewrites alone for admin (session + multi-segment paths). */
export const dynamic = "force-dynamic";

async function proxyToBackend(
  request: NextRequest,
  pathSegments: string[],
  method: "GET" | "POST"
) {
  const rest = pathSegments.join("/");
  const requestUrl = new URL(request.url);
  const backendUrl = `${BACKEND_URL}/admin/${rest}${requestUrl.search}`;

  const cookie = request.headers.get("cookie") ?? "";
  const headers: Record<string, string> = {
    Cookie: cookie,
  };
  const origin = request.headers.get("origin");
  if (origin) headers.Origin = origin;
  const referer = request.headers.get("referer");
  if (referer) headers.Referer = referer;
  const accept = request.headers.get("accept");
  if (accept) headers.Accept = accept;

  const init: RequestInit = { method, headers };

  if (method === "POST") {
    const ct = request.headers.get("content-type");
    if (ct) headers["Content-Type"] = ct;
    const body = await request.text();
    if (body.length > 0) init.body = body;
  }

  const res = await fetch(backendUrl, init);

  const nextRes = new NextResponse(await res.arrayBuffer(), {
    status: res.status,
    headers: {
      "content-type": res.headers.get("content-type") ?? "application/json",
    },
  });
  forwardBackendResponseCookies(res, nextRes, requestUrl);
  return nextRes;
}

export async function GET(
  request: NextRequest,
  ctx: { params: Promise<{ path: string[] }> }
) {
  const { path } = await ctx.params;
  return proxyToBackend(request, path, "GET");
}

export async function POST(
  request: NextRequest,
  ctx: { params: Promise<{ path: string[] }> }
) {
  const { path } = await ctx.params;
  return proxyToBackend(request, path, "POST");
}
