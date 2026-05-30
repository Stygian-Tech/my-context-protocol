/**
 * Builds the `/api/auth/confirm` URL that strips `auth_token` from the current URL.
 * Keeps logic testable without importing Next.js server types.
 */
export function buildAuthConfirmRedirect(requestUrl: string, authToken: string): string {
  const returnUrl = new URL(requestUrl);
  returnUrl.searchParams.delete("auth_token");
  const relative = `${returnUrl.pathname}${returnUrl.search}${returnUrl.hash}`;
  const redirectTo = encodeURIComponent(relative);
  return `/api/auth/confirm?token=${encodeURIComponent(authToken)}&redirect=${redirectTo}`;
}
