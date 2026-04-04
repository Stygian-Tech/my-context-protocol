import Fluent
import Foundation
import Vapor

/// Markdown snapshot of the MCP catalog for `mycontext:catalog` and related tooling.
enum McpCatalogMarkdown {
    static func routingHints(for compiled: CompiledSkill) -> RoutingHints {
        RoutingHints.from(rule: compiled.routingRules.first)
    }

    static func build(db: Database, projectId: UUID) async throws -> String {
        guard let releaseId = try await MCPCatalogService.activeReleaseId(projectId: projectId, db: db) else {
            return Self.emptyMessage(
                reason: "No active release",
                detail: "Open the project in the MyContextProtocol dashboard, ensure a Git repo is connected, run sync, then activate a **ready** release."
            )
        }

        let compiledSkillIds = try await MCPCatalogService.readyCompiledSkillIds(releaseId: releaseId, db: db)
        guard !compiledSkillIds.isEmpty else {
            return Self.emptyMessage(
                reason: "No ready skills in the active release",
                detail: "Fix validation errors for SKILL.md packages in the dashboard or publish a release where all compiled skills are **ready**."
            )
        }

        let toolCaps = try await MCPCatalogService.capabilityDefs(
            compiledSkillIds: compiledSkillIds,
            types: ["tool"],
            db: db
        )
        let resourceCaps = try await MCPCatalogService.capabilityDefs(
            compiledSkillIds: compiledSkillIds,
            types: ["resource"],
            db: db
        )
        let promptCaps = try await MCPCatalogService.capabilityDefs(
            compiledSkillIds: compiledSkillIds,
            types: ["prompt"],
            db: db
        )

        var lines: [String] = [
            "# MCP catalog",
            "",
            "Synthetic tool `\(MCPConstants.catalogToolName)` lists this overview; compiled skills use the `skill:<name>` prefix.",
            "",
        ]

        lines.append("## Tools")
        if toolCaps.isEmpty {
            lines.append("_None (exposure type not set to tool)._")
        } else {
            for cap in toolCaps {
                let c = cap.compiledSkill
                let hints = routingHints(for: c)
                let desc = MCPAgentCopy.mergeRoutingHints(into: c.summary, hints: hints) ?? "(no summary)"
                lines.append("- **`\(cap.capabilityName)`** — \(desc.replacingOccurrences(of: "\n", with: " "))")
            }
        }
        lines.append("")

        lines.append("## Resources")
        if resourceCaps.isEmpty {
            lines.append("_None._")
        } else {
            for cap in resourceCaps {
                guard let meta = CapabilitySchemaBuilder.parseResourceMeta(cap.schemaJson) else { continue }
                let c = cap.compiledSkill
                lines.append("- **\(c.name)** — URI `\(meta.uri)`")
                if let s = c.summary, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    lines.append("  - \(s)")
                }
            }
        }
        lines.append("")

        lines.append("## Prompts")
        if promptCaps.isEmpty {
            lines.append("_None._")
        } else {
            for cap in promptCaps {
                let c = cap.compiledSkill
                let hints = routingHints(for: c)
                let desc = MCPAgentCopy.mergeRoutingHints(into: c.summary, hints: hints) ?? "(no summary)"
                lines.append("- **`\(cap.capabilityName)`** — \(desc.replacingOccurrences(of: "\n", with: " "))")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func emptyMessage(reason: String, detail: String) -> String {
        """
        # MCP catalog

        **\(reason).**

        \(detail)

        Use tool `\(MCPConstants.catalogToolName)` again after the catalog is available.
        """
    }
}
