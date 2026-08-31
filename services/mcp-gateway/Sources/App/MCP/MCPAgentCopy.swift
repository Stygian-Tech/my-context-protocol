import Foundation

/// Human- and agent-facing strings merged into MCP tool/prompt descriptions.
enum MCPAgentCopy {
    private static let maxDescriptionLength = 1800

    static func toolDescription(baseSummary: String?, hints: RoutingHints) -> String? {
        let merged = mergeRoutingHints(into: baseSummary, hints: hints)
        return merged.map(clampDescription)
    }

    static func mergeRoutingHints(into baseSummary: String?, hints: RoutingHints) -> String? {
        var parts: [String] = []
        let base = baseSummary?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let base, !base.isEmpty {
            parts.append(base)
        }
        if let u = hints.useWhen, !u.isEmpty {
            parts.append("When to use:\n" + u.map { "- \($0)" }.joined(separator: "\n"))
        }
        if let a = hints.avoidWhen, !a.isEmpty {
            parts.append("Avoid when:\n" + a.map { "- \($0)" }.joined(separator: "\n"))
        }
        if let f = hints.failureModes, !f.isEmpty {
            parts.append("Failure modes:\n" + f.map { "- \($0)" }.joined(separator: "\n"))
        }
        if hints.invokeFirst == true {
            parts.append("Invoke first: prefer calling this tool early in the session when relevant.")
        }
        if parts.isEmpty { return nil }
        return parts.joined(separator: "\n\n")
    }

    static func initializeInstructions(projectName: String, projectDashboardURL: String?) -> String {
        var lines: [String] = [
            "You are connected to MyContextProtocol project \"\(projectName)\".",
            "Start by calling `\(MCPConstants.resolveContextToolName)` with the current user request and the tools available in your session. It returns active and suggested skills, conflicts, provenance, capability bindings, and a resolution trace.",
            "Use `\(MCPConstants.getSkillToolName)` when you need the complete versioned skill document, and `\(MCPConstants.reportSkillFeedbackToolName)` when observed guidance is missing, ambiguous, incorrect, conflicting, or outdated.",
            "Projects with the explicit legacy compiled-tools switch may additionally expose per-skill tools using the SKILL.md package slug (no `skill:` prefix).",
            "Prefer tools for callable procedures; use resources for long markdown context (`resources/read` with `ctx://skill/...` URIs); prompts expose reusable guidance templates.",
        ]
        if let dash = projectDashboardURL, !dash.isEmpty {
            lines.append("Project dashboard: \(dash)")
        }
        lines.append(
            "If tools/resources are empty, the project may have no active release or no ready skills—sync the connected Git repo and activate a ready release in the dashboard."
        )
        return lines.joined(separator: "\n")
    }

    static func serverDescription(projectName: String) -> String {
        "Hosted MCP skills for project \"\(projectName)\" (MyContextProtocol)."
    }

    private static func clampDescription(_ s: String) -> String {
        if s.count <= maxDescriptionLength { return s }
        let idx = s.index(s.startIndex, offsetBy: maxDescriptionLength - 1)
        return String(s[..<idx]) + "…"
    }
}
