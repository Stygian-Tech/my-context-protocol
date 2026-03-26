import { describe, expect, it } from "vitest";
import { shortCommitLabel } from "./commit-display";

describe("shortCommitLabel", () => {
  it("preserves pending and unknown", () => {
    expect(shortCommitLabel("pending")).toBe("pending");
    expect(shortCommitLabel("unknown")).toBe("unknown");
  });

  it("truncates long SHAs", () => {
    expect(shortCommitLabel("abcdef1234567890")).toBe("abcdef1");
  });
});
