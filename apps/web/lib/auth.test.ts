import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const { get, post } = vi.hoisted(() => ({
  get: vi.fn(),
  post: vi.fn(),
}));

vi.mock("./api", () => ({
  api: { get, post },
  ApiError: class ApiError extends Error {
    status: number;
    constructor(status: number, message: string) {
      super(message);
      this.status = status;
    }
  },
}));

import { stubNextPublicAuthDefaultsUnset } from "@/lib/testing/stub-public-env";
import { ApiError } from "./api";
import { confirmAuth, getCurrentUser, getGitHubLoginUrl, logout } from "./auth";

describe("getGitHubLoginUrl (server / no window)", () => {
  const originalWindow = globalThis.window;

  beforeEach(() => {
    // @ts-expect-error server path
    delete globalThis.window;
    vi.stubEnv("NEXT_PUBLIC_API_URL", "https://api.example.com");
    vi.stubEnv("NEXT_PUBLIC_APP_URL", "https://app.example.com");
  });

  afterEach(() => {
    globalThis.window = originalWindow;
    vi.unstubAllEnvs();
  });

  it("builds URL with env and encodes return_to", () => {
    const u = getGitHubLoginUrl("/projects");
    expect(u.startsWith("https://api.example.com/auth/github?return_to=")).toBe(true);
    expect(u).toContain(encodeURIComponent("https://app.example.com/projects"));
  });

  it("prefixes return path when missing slash", () => {
    const u = getGitHubLoginUrl("x");
    expect(u).toContain(encodeURIComponent("https://app.example.com/x"));
  });

  it("defaults to localhost when env vars are absent", () => {
    stubNextPublicAuthDefaultsUnset();
    const u = getGitHubLoginUrl("/");
    expect(u.startsWith("http://localhost:8080/auth/github?return_to=")).toBe(true);
    expect(u).toContain(encodeURIComponent("http://localhost:3000/"));
  });
});

describe("getGitHubLoginUrl (browser)", () => {
  const originalWindow = globalThis.window;

  beforeEach(() => {
    vi.stubGlobal(
      "window",
      { location: { origin: "https://app.example.com" } } as unknown as Window
    );
  });

  afterEach(() => {
    globalThis.window = originalWindow;
    vi.unstubAllGlobals();
  });

  it("uses /api base and window origin", () => {
    const u = getGitHubLoginUrl("/settings");
    expect(u.startsWith("/api/auth/github?return_to=")).toBe(true);
    expect(u).toContain(encodeURIComponent("https://app.example.com/settings"));
  });
});

describe("auth api wrappers", () => {
  afterEach(() => {
    get.mockReset();
    post.mockReset();
  });

  it("logout posts", async () => {
    post.mockResolvedValueOnce(undefined);
    await logout();
    expect(post).toHaveBeenCalledWith("/auth/logout");
  });

  it("confirmAuth normalizes user", async () => {
    get.mockResolvedValueOnce({
      id: "1",
      plan: "pro",
      app_env: " DEV ",
      non_production_bypasses: true,
    });
    const u = await confirmAuth("tok");
    expect(get).toHaveBeenCalled();
    expect(u?.plan).toBe("pro");
    expect(u?.app_env).toBe("dev");
    expect(u?.non_production_bypasses).toBe(true);
  });

  it("confirmAuth maps plans, envs, and flags", async () => {
    get.mockResolvedValueOnce({
      id: "2",
      plan: "free",
      app_env: "staging",
      internal_pro_bypass: true,
      can_manage_subscription: true,
      non_production_bypasses: null,
    });
    const u = await confirmAuth("t2");
    expect(u?.plan).toBe("free");
    expect(u?.app_env).toBeUndefined();
    expect(u?.internal_pro_bypass).toBe(true);
    expect(u?.can_manage_subscription).toBe(true);
    expect(u?.non_production_bypasses).toBeUndefined();
  });

  it("confirmAuth returns null when API returns empty", async () => {
    get.mockResolvedValueOnce(null);
    expect(await confirmAuth("tok")).toBeNull();
  });

  it("getCurrentUser returns null on 401", async () => {
    get.mockRejectedValueOnce(new ApiError("nope", 401));
    expect(await getCurrentUser()).toBeNull();
  });

  it("getCurrentUser returns null on other errors", async () => {
    get.mockRejectedValueOnce(new Error("network"));
    expect(await getCurrentUser()).toBeNull();
  });

  it("getCurrentUser returns null when me payload is empty", async () => {
    get.mockResolvedValueOnce(null);
    expect(await getCurrentUser()).toBeNull();
  });

  it("getCurrentUser normalizes successful payload", async () => {
    get.mockResolvedValueOnce({
      id: "u1",
      plan: "pro",
      email: null,
      login: "octocat",
      app_env: "local",
      non_production_bypasses: false,
    });
    const u = await getCurrentUser();
    expect(u?.id).toBe("u1");
    expect(u?.email).toBeUndefined();
    expect(u?.login).toBe("octocat");
    expect(u?.app_env).toBe("local");
    expect(u?.non_production_bypasses).toBe(false);
  });
});
