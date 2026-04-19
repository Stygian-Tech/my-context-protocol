import type { CompiledSkill } from "./types";
import type { McpMetadataFieldId } from "./mcp-metadata-editor-validation";

/** Traffic-light heuristic for MCP metadata quality (dashboard; mirrors backend `McpMetadataHealth.tier`). */
export type McpMetadataHealthTier = "red" | "yellow" | "green";

export function metadataHealthTier(skill: CompiledSkill): McpMetadataHealthTier {
  if (skill.status === "not_publishable") return "red";
  const raw = skill.schema_json?.trim() ?? "";
  if (raw) {
    try {
      JSON.parse(raw);
    } catch {
      return "red";
    }
  }
  if (skill.exposure_type === "resource") {
    if (!raw) return "red";
    try {
      const o = JSON.parse(raw) as { uri?: string };
      if (!o.uri?.trim()) return "red";
    } catch {
      return "red";
    }
  }
  if (skill.status === "needs_review") return "yellow";
  if (skill.yaml_frontmatter_present === false) return "yellow";
  if (!skill.skill_body?.trim()) return "yellow";
  if (skill.exposure_type === "resource") {
    const hasRouting =
      (skill.use_when?.length ?? 0) > 0 ||
      (skill.avoid_when?.length ?? 0) > 0 ||
      (skill.failure_modes?.length ?? 0) > 0;
    if (!hasRouting) return "yellow";
  }
  if (skill.status === "ready") return "green";
  return "yellow";
}

/**
 * For {@link McpMetadataHealthTier} `yellow` skills, which editor fields drive the warning so we can outline them in the MCP metadata UI.
 */
export function mcpReviewHighlightFields(skill: CompiledSkill): McpMetadataFieldId[] {
  if (metadataHealthTier(skill) !== "yellow") return [];

  const fields: McpMetadataFieldId[] = [];
  const add = (f: McpMetadataFieldId) => {
    if (!fields.includes(f)) fields.push(f);
  };

  if (skill.status === "needs_review") add("status");
  if (skill.yaml_frontmatter_present === false) add("skill_body");
  if (!skill.skill_body?.trim()) add("skill_body");
  if (skill.exposure_type === "resource") {
    const hasRouting =
      (skill.use_when?.length ?? 0) > 0 ||
      (skill.avoid_when?.length ?? 0) > 0 ||
      (skill.failure_modes?.length ?? 0) > 0;
    if (!hasRouting) {
      add("use_when");
      add("avoid_when");
      add("failure_modes");
    }
  }
  return fields;
}

/**
 * Best field to scroll to for a skill in the blocking (red) tier.
 * Order matches {@link metadataHealthTier} red checks.
 */
export function mcpFocusFieldForBlockingSkill(skill: CompiledSkill): McpMetadataFieldId {
  if (skill.status === "not_publishable") {
    const sum = skill.summary?.trim() ?? "";
    return sum.length === 0 ? "summary" : "status";
  }
  const raw = skill.schema_json?.trim() ?? "";
  if (raw) {
    try {
      JSON.parse(raw);
    } catch {
      return "schema_json";
    }
  } else if (skill.exposure_type === "resource") {
    return "schema_json";
  }
  if (skill.exposure_type === "resource") {
    try {
      const o = JSON.parse(raw) as { uri?: string };
      if (!o.uri?.trim()) return "schema_json";
    } catch {
      return "schema_json";
    }
  }
  return "schema_json";
}
