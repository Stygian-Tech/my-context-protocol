/**
 * Defense-in-depth: only navigate to known third-party hosts from API-provided URLs.
 */

const STRIPE_CHECKOUT_HOSTS = ["checkout.stripe.com", "billing.stripe.com"];
const GITHUB_INSTALL_HOSTS = ["github.com"];

function hostnameOf(urlString: string): string | null {
  try {
    const u = new URL(urlString);
    return u.hostname.toLowerCase();
  } catch {
    return null;
  }
}

export function assertStripeRedirectUrl(urlString: string): void {
  const host = hostnameOf(urlString);
  if (!host || !STRIPE_CHECKOUT_HOSTS.includes(host)) {
    throw new Error("untrusted_stripe_url");
  }
}

/** Allow GitHub itself, or the authenticated installer for this exact project. */
export function assertGitHubInstallUrl(
  urlString: string,
  context?: { origin: string; projectId: string }
): void {
  try {
    const url = new URL(urlString);
    if ((url.protocol !== "https:" && url.protocol !== "http:") || url.username || url.password) {
      throw new Error("untrusted_github_url");
    }
    if (GITHUB_INSTALL_HOSTS.includes(url.hostname.toLowerCase())) return;

    const projects = url.searchParams.getAll("project_id");
    if (
      context &&
      url.origin === new URL(context.origin).origin &&
      url.pathname === "/api/auth/github/app/install" &&
      projects.length === 1 &&
      projects[0].toLowerCase() === context.projectId.toLowerCase()
    ) return;
  } catch {
    throw new Error("untrusted_github_url");
  }
  throw new Error("untrusted_github_url");
}
