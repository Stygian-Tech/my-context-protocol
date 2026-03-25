import { describe, expect, it } from "vitest";
import { buildMcpJsonConfig } from "./clipboard";

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
});
