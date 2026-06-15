import { describe, expect, it } from "vitest";
import { getApiKeyDisplayName } from "./api-key-utils";

describe("api key utils", () => {
  it("falls back to Unnamed key when no name is present", () => {
    expect(getApiKeyDisplayName(null)).toBe("Unnamed key");
    expect(getApiKeyDisplayName("")).toBe("Unnamed key");
  });

  it("keeps a provided name", () => {
    expect(getApiKeyDisplayName("Production Cursor")).toBe("Production Cursor");
  });
});
