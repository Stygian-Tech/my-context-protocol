"use client";

import { useEffect } from "react";
import { usePathname } from "next/navigation";
import { useAuth } from "@/contexts/auth-context";

const PUBLIC_PATHS = ["/login"];

function hasAuthTokenInUrl(): boolean {
  if (typeof window === "undefined") return false;
  return new URLSearchParams(window.location.search).has("auth_token");
}

export function AuthGuard({ children }: { children: React.ReactNode }) {
  const { user, isLoading } = useAuth();
  const pathname = usePathname();

  const isPublic = PUBLIC_PATHS.some((p) => pathname.startsWith(p));
  const isConfirmingOAuth = hasAuthTokenInUrl();

  useEffect(() => {
    if (isLoading || isConfirmingOAuth) return;
    if (!isPublic && !user) {
      window.location.href = `/login?redirect=${encodeURIComponent(pathname)}`;
    }
  }, [user, isLoading, isPublic, isConfirmingOAuth, pathname]);

  if (isLoading || isConfirmingOAuth) {
    return (
      <div className="flex min-h-screen items-center justify-center">
        <div
          className="text-muted-foreground"
          role="status"
          aria-live="polite"
        >
          {isConfirmingOAuth ? "Completing sign-in…" : "Loading…"}
        </div>
      </div>
    );
  }

  if (!isPublic && !user) {
    return null;
  }

  return <>{children}</>;
}
