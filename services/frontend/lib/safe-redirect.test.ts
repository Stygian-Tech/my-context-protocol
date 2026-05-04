import { describe, expect, it } from "vitest";
import { assertSafeRelativeRedirectPath, safeReturnPath } from "./safe-redirect";

describe("safeReturnPath", () => {
  it("allows normal paths", () => {
    expect(safeReturnPath("/dash")).toBe("/dash");
    expect(safeReturnPath("/billing?x=1")).toBe("/billing?x=1");
    expect(safeReturnPath("/")).toBe("/");
  });

  it("trims whitespace", () => {
    expect(safeReturnPath("  /x  ")).toBe("/x");
  });

  it("blocks open redirects", () => {
    expect(safeReturnPath("//evil.com")).toBe("/");
    expect(safeReturnPath("https://evil.com")).toBe("/");
    expect(safeReturnPath("")).toBe("/");
  });

  it("blocks control chars and oversize paths", () => {
    expect(safeReturnPath("/a\0b")).toBe("/");
    expect(safeReturnPath("/x\rx")).toBe("/");
    expect(safeReturnPath("/x\nx")).toBe("/");
    expect(safeReturnPath("/" + "a".repeat(4097))).toBe("/");
  });
});

describe("assertSafeRelativeRedirectPath", () => {
  it("accepts safe paths", () => {
    expect(() => assertSafeRelativeRedirectPath("/ok")).not.toThrow();
  });

  it("rejects unsafe paths", () => {
    expect(() => assertSafeRelativeRedirectPath("//evil")).toThrow();
    expect(() => assertSafeRelativeRedirectPath(null as unknown as string)).toThrow();
    expect(() => assertSafeRelativeRedirectPath("")).toThrow();
  });

  it("rejects CRLF, nul, and long paths", () => {
    expect(() => assertSafeRelativeRedirectPath("/x\rx")).toThrow();
    expect(() => assertSafeRelativeRedirectPath("/x\0")).toThrow();
    expect(() => assertSafeRelativeRedirectPath("/" + "b".repeat(4097))).toThrow();
  });
});
