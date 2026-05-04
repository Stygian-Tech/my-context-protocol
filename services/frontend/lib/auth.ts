import { api, ApiError } from "./api";
import type { User } from "./types";

export function getGitHubLoginUrl(returnTo = "/"): string {
  const baseUrl =
    typeof window !== "undefined" ? "/api" : process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8080";
  const appUrl =
    typeof window !== "undefined"
      ? window.location.origin
      : process.env.NEXT_PUBLIC_APP_URL ?? "http://localhost:3000";
  const returnUrl = `${appUrl}${returnTo.startsWith("/") ? returnTo : `/${returnTo}`}`;
  return `${baseUrl.replace(/\/$/, "")}/auth/github?return_to=${encodeURIComponent(returnUrl)}`;
}

export async function logout(): Promise<void> {
  await api.post("/auth/logout");
}

/** Exchange one-time OAuth handoff token for session. Call when auth_token is in the URL. */
function normalizeUser(u: {
  id: string;
  email?: string | null;
  login?: string | null;
  avatar_url?: string | null;
  plan?: string | null;
  is_admin?: boolean | null;
  internal_pro_bypass?: boolean | null;
  can_manage_subscription?: boolean | null;
  app_env?: string | null;
  non_production_bypasses?: boolean | null;
}): User {
  const rawEnv = u.app_env?.trim().toLowerCase();
  const app_env =
    rawEnv === "local" || rawEnv === "dev" || rawEnv === "prod" ? rawEnv : undefined;
  return {
    id: u.id,
    email: u.email ?? undefined,
    login: u.login ?? undefined,
    avatar_url: u.avatar_url ?? undefined,
    plan: u.plan === "pro" ? "pro" : "free",
    is_admin: Boolean(u.is_admin),
    internal_pro_bypass: Boolean(u.internal_pro_bypass),
    can_manage_subscription: Boolean(u.can_manage_subscription),
    app_env,
    non_production_bypasses:
      u.non_production_bypasses === undefined || u.non_production_bypasses === null
        ? undefined
        : Boolean(u.non_production_bypasses),
  };
}

export async function confirmAuth(token: string): Promise<User | null> {
  const user = await api.get<User>(`/auth/confirm?token=${encodeURIComponent(token)}`);
  return user ? normalizeUser(user) : null;
}

export async function getCurrentUser(): Promise<User | null> {
  try {
    const user = await api.get<User>("/auth/me");
    return user ? normalizeUser(user) : null;
  } catch (err) {
    if (err instanceof ApiError && err.status === 401) {
      return null;
    }
    return null;
  }
}
