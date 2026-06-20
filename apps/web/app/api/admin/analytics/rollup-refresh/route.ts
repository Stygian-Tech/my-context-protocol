import type { NextRequest } from "next/server";
import { proxyAdminToBackend } from "@/lib/admin-backend-proxy";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

export async function POST(request: NextRequest) {
  return proxyAdminToBackend(request, "analytics/rollup-refresh", "POST");
}
