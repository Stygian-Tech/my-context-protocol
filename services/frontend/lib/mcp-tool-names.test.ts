import { describe, expect, it } from "vitest";
import { MYCONTEXT_CATALOG_TOOL_NAME } from "./mcp-tool-names";

describe("MCP tool names", () => {
  it("discovery tool matches backend MCPConstants.catalogToolName", () => {
    expect(MYCONTEXT_CATALOG_TOOL_NAME).toBe("mycontext_catalog");
    expect(MYCONTEXT_CATALOG_TOOL_NAME).not.toContain(":");
  });
});
