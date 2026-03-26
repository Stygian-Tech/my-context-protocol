/**
 * Safe in-app paths only (no protocol, no host). Use for post-login redirect and OAuth handoff.
 */
export function safeReturnPath(input: string | null | undefined): string {
  if (input == null || input === "") return "/";
  const t = input.trim();
  if (!t.startsWith("/")) return "/";
  if (t.startsWith("//")) return "/";
  if (t.includes("\0")) return "/";
  if (t.includes("\r") || t.includes("\n")) return "/";
  if (t.length > 4096) return "/";
  return t;
}

/** Throws if redirect param is missing or not a safe relative path (for Route Handlers). */
export function assertSafeRelativeRedirectPath(redirect: string | null): asserts redirect is string {
  if (redirect == null || redirect === "") {
    throw new Error("missing_redirect");
  }
  const t = redirect.trim();
  if (!t.startsWith("/") || t.startsWith("//") || t.includes("\0")) {
    throw new Error("invalid_redirect");
  }
  if (t.includes("\r") || t.includes("\n")) {
    throw new Error("invalid_redirect");
  }
  if (t.length > 4096) {
    throw new Error("invalid_redirect");
  }
}
