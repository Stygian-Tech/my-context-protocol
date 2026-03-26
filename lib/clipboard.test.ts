import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const { toastSuccess, toastError } = vi.hoisted(() => ({
  toastSuccess: vi.fn(),
  toastError: vi.fn(),
}));

vi.mock("@/lib/toast", () => ({
  toastSuccess,
  toastError,
}));

import { buildMcpJsonConfig, copyTextToClipboard } from "./clipboard";

describe("clipboard helpers", () => {
  it("builds the mcp.json object for a new API key", () => {
    expect(buildMcpJsonConfig("https://example.com/mcp", "mcp_secret_123")).toBe(`{
  "mcpServers": {
    "MyContextProtocol": {
      "url": "https://example.com/mcp",
      "headers": {
        "Authorization": "Bearer mcp_secret_123"
      }
    }
  }
}`);
  });

  describe("copyTextToClipboard", () => {
    const writeText = vi.fn();

    beforeEach(() => {
      writeText.mockReset();
      toastSuccess.mockReset();
      toastError.mockReset();
      vi.stubGlobal("navigator", {
        clipboard: { writeText },
      } as Navigator);
    });

    afterEach(() => {
      vi.unstubAllGlobals();
    });

    it("toasts success when write succeeds", async () => {
      writeText.mockResolvedValueOnce(undefined);
      await copyTextToClipboard("x", { success: "copied", error: "fail" });
      expect(writeText).toHaveBeenCalledWith("x");
      expect(toastSuccess).toHaveBeenCalledWith("copied");
      expect(toastError).not.toHaveBeenCalled();
    });

    it("toasts error when write fails", async () => {
      writeText.mockRejectedValueOnce(new Error("denied"));
      await copyTextToClipboard("x", { success: "copied", error: "fail" });
      expect(toastError).toHaveBeenCalledWith("fail");
      expect(toastSuccess).not.toHaveBeenCalled();
    });
  });
});
