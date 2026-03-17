import { api, ApiError } from "./api";
import type { User } from "./types";

export function getGitHubLoginUrl(returnTo = "/"): string {
  const baseUrl =
    typeof window !== "undefined"
      ? process.env.NEXT_PUBLIC_API_URL ?? ""
      : process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8080";
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

export async function getCurrentUser(): Promise<User | null> {
  try {
    const user = await api.get<User>("/auth/me");
    return user ?? null;
  } catch (err) {
    if (err instanceof ApiError && err.status === 401) {
      return null;
    }
    return null;
  }
}
