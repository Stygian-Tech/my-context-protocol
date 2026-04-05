"use client";

import { useEffect } from "react";
import { Button } from "@/components/ui/button";

export default function Error({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    console.error(error);
  }, [error]);

  return (
    <section
      className="flex min-h-[400px] flex-col items-center justify-center gap-4 p-8"
      aria-labelledby="app-error-heading"
      role="alert"
    >
      <h2 id="app-error-heading" className="text-xl font-semibold">
        Something went wrong
      </h2>
      <p className="text-muted-foreground text-center">
        An unexpected error occurred. You can try again or return to the
        dashboard.
      </p>
      <div className="flex gap-2">
        <Button onClick={() => reset()}>Try again</Button>
        <Button variant="outline" onClick={() => (window.location.href = "/")}>
          Go to Dashboard
        </Button>
      </div>
    </section>
  );
}
