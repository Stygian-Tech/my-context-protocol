"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useState,
} from "react";
import { useRouter } from "next/navigation";
import {
  getCurrentUser,
  getGitHubLoginUrl,
  logout as apiLogout,
} from "@/lib/auth";
import { safeReturnPath } from "@/lib/safe-redirect";
import type { User } from "@/lib/types";

interface AuthContextValue {
  user: User | null;
  isLoading: boolean;
  loginWithGitHub: (returnTo?: string) => void;
  logout: () => Promise<void>;
  refreshUser: () => Promise<void>;
}

const AuthContext = createContext<AuthContextValue | null>(null);

// Module-level guard: prevents multiple confirmAuth calls when React Strict Mode remounts.
// The token is one-time use; a second call would get 401 and consume it before the first succeeds.
const confirmingTokens = new Set<string>();

declare global {
  interface Window {
    __confirmingAuthToken?: string;
  }
}

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const router = useRouter();

  const loadUser = useCallback(async () => {
    try {
      const u = await getCurrentUser();
      // Use functional update: never overwrite existing user with null from a concurrent loadUser
      setUser((prev) => (u !== null ? u : prev ?? null));
      // Recovery: redirect immediately when we have user + auth_failed, before any effect re-run
      if (u && typeof window !== "undefined" && new URLSearchParams(window.location.search).get("error") === "auth_failed") {
        window.location.replace("/");
        return;
      }
    } catch {
      setUser((prev) => (prev ?? null));
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    const params = typeof window !== "undefined" ? new URLSearchParams(window.location.search) : null;
    const authToken = params?.get("auth_token");

    // Add token synchronously at the very start so concurrent effect runs see it.
    // Use both module Set and window flag so it works across module instances (e.g. HMR).
    if (authToken) {
      if (confirmingTokens.has(authToken) || window.__confirmingAuthToken === authToken) {
        return;
      }
      confirmingTokens.add(authToken);
      window.__confirmingAuthToken = authToken;
    }

    if (authToken) {
      const returnUrl = new URL(window.location.href);
      returnUrl.searchParams.delete("auth_token");
      const relative = `${returnUrl.pathname}${returnUrl.search}${returnUrl.hash}`;
      const redirectTo = encodeURIComponent(relative);
      const confirmUrl = `/api/auth/confirm?token=${encodeURIComponent(authToken)}&redirect=${redirectTo}`;
      window.location.replace(confirmUrl);
      return;
    }

    // Only fetch when we don't already have a user. Prevents a subsequent loadUser()
    // (from effect re-run after router.replace) from overwriting valid user with null.
    if (!authToken && !user) {
      queueMicrotask(() => {
        void loadUser();
      });
    }
  }, [loadUser, user]);

  // Recovery: when we have user but URL has auth_failed, do full-page nav so dashboard
  // loads fresh with session cookie (avoids React/Next.js layout transition losing state).
  useEffect(() => {
    if (user && typeof window !== "undefined") {
      const err = new URLSearchParams(window.location.search).get("error");
      if (err === "auth_failed") {
        window.location.replace("/");
      }
    }
  }, [user]);

  const loginWithGitHub = useCallback((returnTo = "/") => {
    returnTo = safeReturnPath(returnTo);
    window.location.href = getGitHubLoginUrl(returnTo);
  }, []);

  const logout = useCallback(async () => {
    await apiLogout();
    setUser(null);
    router.push("/login");
  }, [router]);

  return (
    <AuthContext.Provider value={{ user, isLoading, loginWithGitHub, logout, refreshUser: loadUser }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) {
    throw new Error("useAuth must be used within AuthProvider");
  }
  return ctx;
}
