import Foundation

enum MCPConstants {
    /// Synthetic MCP discovery tool. Colon-free so editors/clients that mishandle `:` in tool names stay compatible.
    static let catalogToolName = "mycontext_catalog"
    static let serverVersion = "1.0.0"

    /// Wire name for a compiled skill exposed as an MCP tool or prompt (the `SKILL.md` package slug only).
    static func compiledCapabilityWireName(skillSlug: String) -> String {
        skillSlug
    }
}
