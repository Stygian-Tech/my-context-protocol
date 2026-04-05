/** Editable regions in the release MCP metadata dialog (matches form sections). */
export type McpMetadataFieldId =
  | "exposure_type"
  | "risk_level"
  | "status"
  | "use_when"
  | "avoid_when"
  | "failure_modes"
  | "invoke_first"
  | "skill_body"
  | "summary"
  | "schema_json"
  /** Server or unknown error — show banner only, no field ring. */
  | "_form";

/** Stable DOM id for scrolling to a field in the MCP metadata editor (`SkillEditorRow`). */
export function mcpMetadataFieldAnchorId(
  skillId: string,
  field: McpMetadataFieldId
): string {
  return `mcp-metadata-editor-${skillId}-${field}`;
}

export type McpMetadataIssue = {
  field: McpMetadataFieldId;
  message: string;
};

export function uniqueIssueMessages(issues: McpMetadataIssue[]): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const { message } of issues) {
    const t = message.trim();
    if (!t || seen.has(t)) continue;
    seen.add(t);
    out.push(t);
  }
  return out;
}

export function firstIssueForField(
  issues: McpMetadataIssue[],
  field: McpMetadataFieldId
): string | undefined {
  return issues.find((i) => i.field === field)?.message;
}

/**
 * Client-side checks before PATCH.
 * Any non-empty MCP capability JSON is validated on save (even if the textarea was not edited),
 * so broken or resource-incomplete JSON is always highlighted in the modal.
 */
export function validateMcpMetadataBeforeSave(input: {
  schemaJson: string;
  exposure: string;
}): McpMetadataIssue[] {
  const t = input.schemaJson.trim();
  if (t === "") return [];

  let parsed: unknown;
  try {
    parsed = JSON.parse(input.schemaJson);
  } catch {
    return [
      {
        field: "schema_json",
        message:
          "MCP capability JSON is not valid JSON. Fix the syntax, or use Reset to defaults to rebuild it from this skill.",
      },
    ];
  }

  if (input.exposure === "resource") {
    const o = parsed as { uri?: unknown };
    const u = typeof o.uri === "string" ? o.uri.trim() : "";
    if (!u) {
      return [
        {
          field: "schema_json",
          message:
            "Resource exposure requires a non-empty uri in the JSON (for example ctx://skill/…). Reset to defaults if you are unsure.",
        },
      ];
    }
  }

  return [];
}

/** Map API error text to a field when the server does not send structured errors. */
export function mapApiDetailToMcpField(detail: string): McpMetadataFieldId {
  const r = detail.toLowerCase();
  if (r.includes("schema_json") || r.includes("valid json")) {
    return "schema_json";
  }
  return "_form";
}
