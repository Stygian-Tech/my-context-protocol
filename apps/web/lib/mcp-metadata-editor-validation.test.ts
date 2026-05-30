import { describe, expect, it } from "vitest";
import {
  mapApiDetailToMcpField,
  uniqueIssueMessages,
  validateMcpMetadataBeforeSave,
} from "./mcp-metadata-editor-validation";

describe("validateMcpMetadataBeforeSave", () => {
  it("allows empty custom JSON (reset path)", () => {
    expect(
      validateMcpMetadataBeforeSave({
        schemaJson: "   ",
        exposure: "resource",
      })
    ).toEqual([]);
  });

  it("rejects invalid JSON", () => {
    const issues = validateMcpMetadataBeforeSave({
      schemaJson: "{",
      exposure: "tool",
    });
    expect(issues).toHaveLength(1);
    expect(issues[0].field).toBe("schema_json");
  });

  it("requires uri for resource when JSON is custom", () => {
    const issues = validateMcpMetadataBeforeSave({
      schemaJson: '{"mimeType":"text/markdown"}',
      exposure: "resource",
    });
    expect(issues).toHaveLength(1);
    expect(issues[0].field).toBe("schema_json");
  });

  it("does not require uri for tool", () => {
    expect(
      validateMcpMetadataBeforeSave({
        schemaJson: '{"type":"object","properties":{}}',
        exposure: "tool",
      })
    ).toEqual([]);
  });

  it("validates non-empty JSON even when not marked dirty", () => {
    const issues = validateMcpMetadataBeforeSave({
      schemaJson: "{bad",
      exposure: "tool",
    });
    expect(issues).toHaveLength(1);
  });
});

describe("mapApiDetailToMcpField", () => {
  it("maps schema errors", () => {
    expect(mapApiDetailToMcpField("schema_json must be valid JSON")).toBe("schema_json");
    expect(mapApiDetailToMcpField("Must be valid JSON")).toBe("schema_json");
  });

  it("falls back to form", () => {
    expect(mapApiDetailToMcpField("Release not found")).toBe("_form");
  });
});

describe("uniqueIssueMessages", () => {
  it("dedupes messages", () => {
    expect(
      uniqueIssueMessages([
        { field: "schema_json", message: "a" },
        { field: "schema_json", message: "a" },
        { field: "summary", message: "b" },
      ])
    ).toEqual(["a", "b"]);
  });
});
