import { api } from "./api";

export interface AdminPlatformMetrics {
  total_users: number;
  total_projects: number;
  total_mcp_calls: number;
}

export interface AdminLookupResult {
  account_id: string;
  is_admin: boolean;
  paywall_bypass: boolean;
}

export async function fetchAdminMetrics(): Promise<AdminPlatformMetrics> {
  return api.get<AdminPlatformMetrics>("/admin/metrics");
}

export async function adminLookup(
  body:
    | { github_login: string }
    | { github_id: string }
    | { email: string }
): Promise<AdminLookupResult> {
  return api.post<AdminLookupResult>("/admin/lookup", body);
}

export async function adminUpdateFlags(body: {
  account_id: string;
  is_admin?: boolean;
  paywall_bypass?: boolean;
}): Promise<void> {
  await api.post<void>("/admin/account-flags", body);
}
