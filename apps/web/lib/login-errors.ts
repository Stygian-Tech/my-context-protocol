/** Maps backend / API redirect `error` query values to user-facing copy (no secrets). */
export function loginErrorMessage(code: string | null): string | null {
  if (!code) return null;
  switch (code) {
    case "auth_failed":
      return "Sign-in failed. Please try again.";
    case "missing_params":
      return "The sign-in link was incomplete. Start sign-in again.";
    case "invalid_redirect":
      return "Sign-in could not continue safely. Start sign-in again.";
    default:
      return "Sign-in could not be completed. Please try again.";
  }
}
