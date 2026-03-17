"use client";

import { Suspense } from "react";
import { useSearchParams } from "next/navigation";
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

function LoginContent() {
  const { loginWithGitHub, isLoading: authLoading, user } = useAuth();
  const searchParams = useSearchParams();
  const returnTo = searchParams.get("redirect") ?? "/";

  if (authLoading) {
    return (
      <div className="flex min-h-screen items-center justify-center">
        <div className="text-muted-foreground">Loading...</div>
      </div>
    );
  }

  if (user) {
    window.location.href = returnTo;
    return null;
  }

  return (
    <div className="flex min-h-screen items-center justify-center p-4">
      <Card className="w-full max-w-md">
        <CardHeader>
          <CardTitle>MyContextProtocol</CardTitle>
          <CardDescription>
            Sign in with your Git host to access the dashboard
          </CardDescription>
        </CardHeader>
        <CardContent>
          <Button
            onClick={() => loginWithGitHub(returnTo)}
            className="w-full"
            variant="outline"
          >
            <GithubIcon className="mr-2 h-4 w-4" />
            Sign in with GitHub
          </Button>
        </CardContent>
      </Card>
    </div>
  );
}

export default function LoginPage() {
  return (
    <Suspense fallback={
      <div className="flex min-h-screen items-center justify-center">
        <div className="text-muted-foreground">Loading...</div>
      </div>
    }>
      <LoginContent />
    </Suspense>
  );
}
