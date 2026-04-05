"use client";

export default function GlobalError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  const message = error?.message?.trim();
  const digest = error?.digest;
  return (
    <html>
      <body>
        <div className="flex min-h-screen flex-col items-center justify-center gap-4 p-8">
          <h2 className="text-xl font-semibold">Something Went Wrong</h2>
          <p className="text-muted-foreground text-center">
            A critical error occurred. Please refresh the page.
          </p>
          {message ? (
            <pre className="bg-muted max-w-lg overflow-auto rounded-md p-3 text-left text-xs leading-relaxed whitespace-pre-wrap">
              {message}
            </pre>
          ) : null}
          {digest ? (
            <p className="text-muted-foreground font-mono text-xs">Digest: {digest}</p>
          ) : null}
          <button
            onClick={() => reset()}
            className="rounded-lg bg-primary px-4 py-2 text-primary-foreground"
          >
            Try again
          </button>
        </div>
      </body>
    </html>
  );
}
