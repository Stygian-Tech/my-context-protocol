import Foundation

enum MCPConstants {
    /// Hidden one-release compatibility alias for the former catalog surface.
    static let catalogToolName = "mycontext_catalog"
    static let resolveContextToolName = "resolve_context"
    static let getSkillToolName = "get_skill"
    static let reportSkillFeedbackToolName = "report_skill_feedback"

    /// The only runtime tools advertised to agents by default.
    static let runtimeToolNames = [resolveContextToolName, getSkillToolName, reportSkillFeedbackToolName]

    /// Compatibility names remain callable for one release, but are intentionally omitted from `tools/list`.
    static let hiddenRuntimeToolAliases = [catalogToolName, "discover_skills", "list_capabilities"]
    static let callableRuntimeToolNames = runtimeToolNames + hiddenRuntimeToolAliases
    static let reservedRuntimeToolNames = Set(callableRuntimeToolNames)
    static let legacyCompiledToolsPreferenceKey = "legacy_compiled_tools_enabled"
    static let serverVersion = "1.2.0"

    static func isReservedRuntimeToolName(_ name: String) -> Bool {
        reservedRuntimeToolNames.contains(name)
    }

    /// Wire name for a compiled skill exposed as an MCP tool or prompt (the `SKILL.md` package slug only).
    static func compiledCapabilityWireName(skillSlug: String) -> String {
        skillSlug
    }
}
