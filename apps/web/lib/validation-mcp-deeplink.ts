import type { McpMetadataFieldId } from "@/lib/mcp-metadata-editor-validation";
import type { CompiledSkill, ValidationErrorEntry } from "@/lib/types";

/** Normalize repo-relative paths for matching validation `path` to `CompiledSkill.path`. */
export function normalizeValidationSkillPath(path: string): string {
  let t = path.trim();
  if (t.startsWith("./")) {
    t = t.slice(2);
  }
  while (t.includes("//")) {
    t = t.replaceAll("//", "/");
  }
  return t;
}

/**
 * Maps ingest validation issue codes and copy to the MCP metadata editor field to scroll/focus.
 * Repo/YAML body issues use `skill_body`; MCP JSON uses `schema_json`; routing lists use `use_when`, etc.
 */
export function mcpFieldForValidationIssue(entry: ValidationErrorEntry): McpMetadataFieldId {
  const c = (entry.code ?? "").toLowerCase();
  const msg = `${entry.message} ${entry.summary ?? ""} ${entry.fix_hint ?? ""}`.toLowerCase();
  const p = entry.path.toLowerCase();

  // Structured codes (pipeline + fixtures)
  if (c === "skill_exposure_review") return "exposure_type";
  if (c === "skill_routing_thin") return "use_when";
  if (c === "skill_description_missing") return "summary";
  if (c === "skill_risk_medium" || c === "risk_tier_blocked") return "risk_level";
  if (c === "invalid_json_schema" || c === "invalid_schema") return "schema_json";
  if (c === "resource_use_when_required") return "use_when";
  if (c === "duplicate_capability") return "summary";
  if (c === "no_yaml_frontmatter" || c === "description_truncated") return "skill_body";

  if (
    c === "skill_prompt_length" ||
    c === "skill_body_large" ||
    c === "skill_body_too_large" ||
    c === "skill_empty_file" ||
    c.startsWith("skill_name") ||
    c === "skill_missing_name" ||
    c === "skill_ingest_error" ||
    c === "legacy_validation" ||
    c === "legacy_warning"
  ) {
    return "skill_body";
  }

  // Heuristics when code is missing or unknown
  if (
    msg.includes("inputschema") ||
    msg.includes("input_schema") ||
    msg.includes("valid json") ||
    msg.includes("json schema") ||
    msg.includes("mcp capability json")
  ) {
    return "schema_json";
  }
  if (
    msg.includes("use_when") ||
    (msg.includes("resource") && msg.includes("front matter")) ||
    msg.includes("read when")
  ) {
    return "use_when";
  }
  if (msg.includes("avoid_when") || msg.includes("skip when")) return "avoid_when";
  if (msg.includes("failure_mode") || msg.includes("fallback")) return "failure_modes";
  if (msg.includes("invoke_first")) return "invoke_first";
  if (msg.includes("risk_level") || msg.includes("starter plan") || msg.includes("high-risk")) {
    return "risk_level";
  }
  if (msg.includes("description") && (msg.includes("truncate") || msg.includes("character"))) {
    return "summary";
  }
  if (msg.includes("duplicate") && (msg.includes("name") || msg.includes("capability"))) {
    return "summary";
  }
  if (msg.includes("yaml") || msg.includes("front matter") || p.endsWith("skill.md")) {
    return "skill_body";
  }

  return "skill_body";
}

/** Strip trailing `SKILL.md` so report paths align with package paths on compiled skills. */
export function validationPathToPackagePath(path: string): string {
  const n = normalizeValidationSkillPath(path);
  return n.replace(/\/SKILL\.md$/i, "");
}

/** Match validation `path` to a compiled skill row for this release. */
export function findCompiledSkillForValidationPath(
  skills: CompiledSkill[] | undefined,
  path: string
): CompiledSkill | undefined {
  if (!skills?.length) return undefined;
  const normalized = normalizeValidationSkillPath(path);
  const asPackage = validationPathToPackagePath(path);

  const direct = skills.find((s) => s.path === normalized);
  if (direct) return direct;
  const loose = skills.find((s) => s.path === path.trim());
  if (loose) return loose;

  const byPackage = skills.find((s) => s.path === asPackage);
  if (byPackage) return byPackage;

  // Longest skill path that matches as a directory prefix of the report path (or vice versa).
  const candidates = skills
    .filter((s) => {
      const sp = s.path;
      return (
        normalized.startsWith(sp + "/") ||
        sp.startsWith(normalized + "/") ||
        asPackage === sp ||
        asPackage.startsWith(sp + "/") ||
        sp.startsWith(asPackage + "/")
      );
    })
    .sort((a, b) => b.path.length - a.path.length);
  if (candidates[0]) return candidates[0];

  const byPrefix = skills
    .filter((s) => normalized.startsWith(s.path) || s.path.startsWith(normalized))
    .sort((a, b) => b.path.length - a.path.length);
  return byPrefix[0];
}

/** Short label for buttons / aria (not sentence case sentences). */
export function mcpFieldShortLabel(field: McpMetadataFieldId): string {
  switch (field) {
    case "exposure_type":
      return "Exposure";
    case "risk_level":
      return "Risk";
    case "status":
      return "Publish status";
    case "use_when":
      return "use_when";
    case "avoid_when":
      return "avoid_when";
    case "failure_modes":
      return "failure_modes";
    case "invoke_first":
      return "invoke_first";
    case "skill_body":
      return "Skill body";
    case "summary":
      return "Summary";
    case "schema_json":
      return "MCP capability JSON";
    case "_form":
      return "Form";
    default:
      return field;
  }
}
