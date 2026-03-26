import { describe, expect, it } from "vitest";
import { pluralEn } from "./pluralize";

describe("pluralEn", () => {
  it("uses singular for 1 and -1", () => {
    expect(pluralEn(1, "log", "logs")).toBe("log");
    expect(pluralEn(-1, "log", "logs")).toBe("log");
  });

  it("uses plural for 0 and other magnitudes", () => {
    expect(pluralEn(0, "log", "logs")).toBe("logs");
    expect(pluralEn(2, "log", "logs")).toBe("logs");
    expect(pluralEn(10, "entry", "entries")).toBe("entries");
  });
});
