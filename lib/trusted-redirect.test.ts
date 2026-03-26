import { describe, expect, it } from "vitest";
import { assertGitHubInstallUrl, assertStripeRedirectUrl } from "./trusted-redirect";

describe("assertStripeRedirectUrl", () => {
  it("allows Stripe hosts", () => {
    expect(() =>
      assertStripeRedirectUrl("https://checkout.stripe.com/c/pay/cs_test_123")
    ).not.toThrow();
    expect(() => assertStripeRedirectUrl("https://billing.stripe.com/p/session/xyz")).not.toThrow();
  });

  it("rejects other hosts", () => {
    expect(() => assertStripeRedirectUrl("https://evil.com")).toThrow();
    expect(() => assertStripeRedirectUrl("https://checkout.stripe.com.attacker.com/x")).toThrow();
  });

  it("rejects strings that do not parse as URLs", () => {
    expect(() => assertStripeRedirectUrl("not a url at all")).toThrow();
  });

});

describe("assertGitHubInstallUrl", () => {
  it("allows github.com", () => {
    expect(() => assertGitHubInstallUrl("https://github.com/apps/foo/installations/new")).not.toThrow();
    expect(() =>
      assertGitHubInstallUrl("http://github.com/apps/foo/installations/new")
    ).not.toThrow();
  });

  it("rejects other hosts", () => {
    expect(() => assertGitHubInstallUrl("https://evil.githubfake.com")).toThrow();
    expect(() => assertGitHubInstallUrl("https://sub.github.com/foo")).toThrow();
  });

  it("rejects non http(s) schemes on github host", () => {
    expect(() => assertGitHubInstallUrl("ftp://github.com/apps/foo")).toThrow();
  });
});
