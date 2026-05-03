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

export function assertGitHubInstallUrl(urlString: string): void {
  const host = hostnameOf(urlString);
  if (!host || !GITHUB_INSTALL_HOSTS.includes(host)) {
    throw new Error("untrusted_github_url");
  }
  try {
    const u = new URL(urlString);
    if (u.protocol !== "https:" && u.protocol !== "http:") {
      throw new Error("untrusted_github_url");
    }
  } catch {
    throw new Error("untrusted_github_url");
  }
}
