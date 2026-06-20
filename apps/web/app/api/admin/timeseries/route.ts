import type { NextRequest } from "next/server";
import { proxyAdminToBackend } from "@/lib/admin-backend-proxy";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

export async function GET(request: NextRequest) {
  return proxyAdminToBackend(request, "timeseries", "GET");
}
