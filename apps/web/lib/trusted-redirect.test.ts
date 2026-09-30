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


describe("project-scoped GitHub installation redirects", () => {
  const context = { origin: "https://testing.mycontextprotocol.dev", projectId: "E21A4021-D807-4E6A-81D2-3811C93939C6" };
  const url = `${context.origin}/api/auth/github/app/install?project_id=e21a4021-d807-4e6a-81d2-3811c93939c6&owner=owner&repo=skills`;

  it("allows the backend-shaped authenticated installer for the same project and origin", () => {
    expect(() => assertGitHubInstallUrl(url, context)).not.toThrow();
    expect(() => assertGitHubInstallUrl("https://github.com/apps/foo/installations/new", context)).not.toThrow();
  });

  it("requires explicit project context for the local installer", () => {
    expect(() => assertGitHubInstallUrl(url)).toThrow("untrusted_github_url");
  });

  it.each([
    "https://attacker.example/api/auth/github/app/install?project_id=E21A4021-D807-4E6A-81D2-3811C93939C6",
    "http://testing.mycontextprotocol.dev/api/auth/github/app/install?project_id=E21A4021-D807-4E6A-81D2-3811C93939C6",
    "https://testing.mycontextprotocol.dev:444/api/auth/github/app/install?project_id=E21A4021-D807-4E6A-81D2-3811C93939C6",
    "https://testing.mycontextprotocol.dev/api/auth/github/app/callback?project_id=E21A4021-D807-4E6A-81D2-3811C93939C6",
    "https://testing.mycontextprotocol.dev/api/auth/github/app/install/extra?project_id=E21A4021-D807-4E6A-81D2-3811C93939C6",
    "https://testing.mycontextprotocol.dev/api/auth/github/app/install?project_id=another-project",
    "https://testing.mycontextprotocol.dev/api/auth/github/app/install",
    "https://testing.mycontextprotocol.dev/api/auth/github/app/install?project_id=E21A4021-D807-4E6A-81D2-3811C93939C6&project_id=another-project",
    "https://user:password@testing.mycontextprotocol.dev/api/auth/github/app/install?project_id=E21A4021-D807-4E6A-81D2-3811C93939C6",
    "javascript:alert(1)",
  ])("rejects an untrusted installation target: %s", (target) => {
    expect(() => assertGitHubInstallUrl(target, context)).toThrow("untrusted_github_url");
  });
});
