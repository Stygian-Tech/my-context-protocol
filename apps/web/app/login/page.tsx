"use client";

import { Suspense, useEffect } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { useAuth } from "@/contexts/auth-context";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { GithubIcon } from "lucide-react";
import { safeReturnPath } from "@/lib/safe-redirect";
import { MAIN_CONTENT_ID } from "@/lib/a11y";
import { loginErrorMessage } from "@/lib/login-errors";

function LoginContent() {
  const { loginWithGitHub, isLoading: authLoading, user } = useAuth();
  const router = useRouter();
  const searchParams = useSearchParams();
  const returnTo = safeReturnPath(searchParams.get("redirect") ?? "/");
  const loginError = loginErrorMessage(searchParams.get("error"));

  useEffect(() => {
    if (!authLoading && user) {
      router.replace(returnTo);
    }
  }, [authLoading, user, returnTo, router]);

  if (authLoading) {
    return (
      <div className="flex min-h-screen items-center justify-center">
        <div
          className="text-muted-foreground"
          role="status"
          aria-live="polite"
        >
          Loading…
        </div>
      </div>
    );
  }

  if (user) {
    return null;
  }

  return (
    <main
      id={MAIN_CONTENT_ID}
      tabIndex={-1}
      aria-label="Sign in"
      className="flex min-h-screen items-center justify-center p-4"
    >
      <Card className="w-full max-w-md">
        <CardHeader>
          <CardTitle>
            <h1 className="text-base leading-snug font-medium">
              MyContextProtocol
            </h1>
          </CardTitle>
          <CardDescription>
            Sign in with your Git host to access the dashboard
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          {loginError ? (
            <p
              className="rounded-md border border-destructive/40 bg-destructive/5 px-3 py-2 text-sm text-destructive"
              role="alert"
            >
              {loginError}
            </p>
          ) : null}
          <Button
            onClick={() => loginWithGitHub(returnTo)}
            className="w-full"
            variant="outline"
          >
            <GithubIcon className="mr-2 h-4 w-4" aria-hidden />
            Sign in with GitHub
          </Button>
        </CardContent>
      </Card>
    </main>
  );
}

export default function LoginPage() {
  return (
    <Suspense
      fallback={
        <div className="flex min-h-screen items-center justify-center">
          <div
            className="text-muted-foreground"
            role="status"
            aria-live="polite"
          >
            Loading…
          </div>
        </div>
      }
    >
      <LoginContent />
    </Suspense>
  );
}
