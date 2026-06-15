import { describe, expect, it } from "vitest";
import { buildAuthConfirmRedirect } from "./auth-token-handoff";

describe("buildAuthConfirmRedirect", () => {
  it("strips auth_token and encodes redirect", () => {
    const u = "https://app.example.com/dash?auth_token=sekret&x=1#frag";
    expect(buildAuthConfirmRedirect(u, "sekret")).toBe(
      "/api/auth/confirm?token=sekret&redirect=" +
        encodeURIComponent("/dash?x=1#frag")
    );
  });

  it("handles token with special characters", () => {
    const u = "https://h.test/?auth_token=a%2Bb";
    const out = buildAuthConfirmRedirect(u, "a+b");
    expect(out).toContain("token=a%2Bb");
  });
});
