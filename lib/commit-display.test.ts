import { describe, expect, it } from "vitest";
import { shortCommitLabel } from "./commit-display";

describe("shortCommitLabel", () => {
  it("preserves pending and unknown", () => {
    expect(shortCommitLabel("pending")).toBe("pending");
    expect(shortCommitLabel("unknown")).toBe("unknown");
  });

  it("uses em dash for empty", () => {
    expect(shortCommitLabel("")).toBe("—");
    expect(shortCommitLabel("   ")).toBe("—");
  });

  it("leaves short SHAs as-is", () => {
    expect(shortCommitLabel("abc")).toBe("abc");
    expect(shortCommitLabel("abcdefg")).toBe("abcdefg");
  });

  it("truncates long SHAs", () => {
    expect(shortCommitLabel("abcdef1234567890")).toBe("abcdef1");
  });
});
