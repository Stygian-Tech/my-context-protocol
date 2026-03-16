import { api, ApiError } from "./api";
import type { User } from "./types";

export interface LoginCredentials {
  email: string;
  password: string;
}

export async function login(credentials: LoginCredentials): Promise<User> {
  const response = await api.post<{ user?: User }>("/auth/login", credentials);
  return (response as { user: User }).user ?? (response as User);
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
