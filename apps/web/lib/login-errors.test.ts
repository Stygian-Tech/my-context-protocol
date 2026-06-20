import { describe, expect, it } from "vitest";
import { loginErrorMessage } from "./login-errors";

describe("loginErrorMessage", () => {
  it("returns null for missing code", () => {
    expect(loginErrorMessage(null)).toBeNull();
  });

  it("maps known error codes", () => {
    expect(loginErrorMessage("auth_failed")).toContain("failed");
    expect(loginErrorMessage("missing_params")).toContain("incomplete");
    expect(loginErrorMessage("invalid_redirect")).toContain("safely");
  });

  it("falls back for unknown codes", () => {
    expect(loginErrorMessage("unknown")).toContain("could not be completed");
  });
});
