import Fluent
import Foundation

enum McpCatalogRouter {
    static func route(arguments: [String: String], db: Database, projectId: UUID) async throws -> String {
        let mode = resolvedMode(arguments)
        switch mode {
        case "overview":
            return try await McpCatalogMarkdown.build(db: db, projectId: projectId)
        case "route":
            return try await routeTask(arguments: arguments, db: db, projectId: projectId)
        case "skill":
            return try await skillBody(arguments: arguments, db: db, projectId: projectId)
        default:
            return """
            # MCP catalog

            Unknown mode `\(mode)`.

            Use `overview`, `route`, or `skill`.
            """
        }
    }

    private static func resolvedMode(_ arguments: [String: String]) -> String {
        if let raw = arguments["mode"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !raw.isEmpty {
            return raw
        }
        if let skill = arguments["skill"]?.trimmingCharacters(in: .whitespacesAndNewlines), !skill.isEmpty {
            return "skill"
        }
        if let task = arguments["task"]?.trimmingCharacters(in: .whitespacesAndNewlines), !task.isEmpty {
            return "route"
        }
        return "overview"
    }

    private static func routeTask(arguments: [String: String], db: Database, projectId: UUID) async throws -> String {
        let rows = try await catalogRows(db: db, projectId: projectId)
        guard !rows.isEmpty else {
            return try await McpCatalogMarkdown.buildGenerated(db: db, projectId: projectId)
        }

        let task = arguments["task"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let limit = routeLimit(arguments["limit"])
        let ranked = rows
            .map { row in ScoredCatalogRow(row: row, score: score(row: row, task: task)) }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.row.capability.type != rhs.row.capability.type {
                    return lhs.row.capability.type < rhs.row.capability.type
                }
                return lhs.row.compiled.name < rhs.row.compiled.name
            }
            .prefix(limit)

        var lines: [String] = [
            "# MCP catalog route",
            ""
        ]
        if task.isEmpty {
            lines.append("No task was provided, so results are ordered by routing priority and skill name.")
        } else {
            lines.append("Task: \(task)")
        }
        lines.append("")
        lines.append("Call/read the first relevant skill before proceeding with the task.")
        lines.append("")

        for (idx, scored) in ranked.enumerated() {
            let row = scored.row
            lines.append("\(idx + 1). **\(row.compiled.name)** (`\(row.capability.type)`, score \(scored.score))")
            if let summary = row.compiled.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
                lines.append("   - Summary: \(summary.replacingOccurrences(of: "\n", with: " "))")
            }
            lines.append("   - Next action: \(nextAction(row))")
            let rationale = routingRationale(row: row)
            if !rationale.isEmpty {
                lines.append("   - Routing rationale: \(rationale)")
            }
            lines.append("   - Full skill via tool: `tools/call \(MCPConstants.catalogToolName)` with `mode=skill` and `skill=\(row.compiled.name)`")
        }

        return lines.joined(separator: "\n")
    }

    private static func skillBody(arguments: [String: String], db: Database, projectId: UUID) async throws -> String {
        guard let query = arguments["skill"]?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else {
            return """
            # MCP catalog skill

            Missing `skill`. Pass a skill slug, capability name, path, or `ctx://skill/...` URI.
            """
        }

        let rows = try await catalogRows(db: db, projectId: projectId)
        guard let row = rows.first(where: { matches(row: $0, query: query) }) else {
            return """
            # MCP catalog skill

            Skill not found: \(query)

            Call `\(MCPConstants.catalogToolName)` with `mode=route` and the current `task` to find matching skills.
            """
        }

        let compiled = row.compiled
        var lines = [
            "# \(compiled.name)",
            "",
            "Exposure: \(row.capability.type)",
            "Path: \(compiled.path)",
            "Next action: \(nextAction(row))"
        ]
        if let summary = compiled.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            lines.append("Summary: \(summary)")
        }
        lines.append("")
        lines.append("---")
        lines.append("")
        lines.append(compiled.skillBody?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        return lines.joined(separator: "\n")
    }

    private static func catalogRows(db: Database, projectId: UUID) async throws -> [CatalogRow] {
        guard let releaseId = try await MCPCatalogService.activeReleaseId(projectId: projectId, db: db) else {
            return []
        }
        let compiledSkillIds = try await MCPCatalogService.readyCompiledSkillIds(releaseId: releaseId, db: db)
        let caps = try await MCPCatalogService.capabilityDefs(
            compiledSkillIds: compiledSkillIds,
            types: ["tool", "resource", "prompt"],
            db: db
        )
        return caps.map { cap in
            CatalogRow(
                capability: cap,
                compiled: cap.compiledSkill,
                hints: McpCatalogMarkdown.routingHints(for: cap.compiledSkill)
            )
        }
    }

    private static func routeLimit(_ raw: String?) -> Int {
        guard let raw, let value = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else { return 5 }
        return min(max(value, 1), 20)
    }

    private static func score(row: CatalogRow, task: String) -> Int {
        var total = row.hints.invokeFirst == true ? 3 : 0
        let tokens = tokenize(task)
        guard !tokens.isEmpty else { return total }

        total += score(tokens: tokens, in: row.compiled.name, weight: 10)
        total += score(tokens: tokens, in: row.capability.capabilityName, weight: 8)
        total += score(tokens: tokens, in: row.capability.type, weight: 2)
        total += score(tokens: tokens, in: row.compiled.summary, weight: 5)
        total += score(tokens: tokens, in: row.hints.useWhen?.joined(separator: " "), weight: 7)
        total += score(tokens: tokens, in: row.hints.failureModes?.joined(separator: " "), weight: 2)
        total += score(tokens: tokens, in: String((row.compiled.skillBody ?? "").prefix(2000)), weight: 1)
        total -= score(tokens: tokens, in: row.hints.avoidWhen?.joined(separator: " "), weight: 8)
        return total
    }

    private static func score(tokens: [String], in text: String?, weight: Int) -> Int {
        guard let text else { return 0 }
        let haystack = text.lowercased()
        return tokens.reduce(0) { partial, token in
            haystack.contains(token) ? partial + weight : partial
        }
    }

    private static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
    }

    private static func matches(row: CatalogRow, query: String) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        let decoded = normalized.removingPercentEncoding ?? normalized
        let candidates = [
            row.compiled.name,
            row.capability.capabilityName,
            row.compiled.path,
            resourceURI(row) ?? "",
            resourceURI(row)?.removingPercentEncoding ?? ""
        ].map { $0.lowercased() }
        return candidates.contains(normalized) || candidates.contains(decoded)
    }

    private static func nextAction(_ row: CatalogRow) -> String {
        switch row.capability.type {
        case "tool":
            return "`tools/call \(row.capability.capabilityName)`"
        case "resource":
            if let uri = resourceURI(row) {
                return "`resources/read \(uri)`"
            }
            return "`resources/list`, then `resources/read` for \(row.compiled.name)"
        case "prompt":
            return "`prompts/get \(row.capability.capabilityName)`"
        default:
            return "`\(row.capability.type)` capability \(row.capability.capabilityName)"
        }
    }

    private static func routingRationale(row: CatalogRow) -> String {
        var parts: [String] = []
        if row.hints.invokeFirst == true {
            parts.append("invoke first")
        }
        if let useWhen = row.hints.useWhen, !useWhen.isEmpty {
            parts.append("use when: \(useWhen.joined(separator: "; "))")
        }
        if let avoidWhen = row.hints.avoidWhen, !avoidWhen.isEmpty {
            parts.append("avoid when: \(avoidWhen.joined(separator: "; "))")
        }
        if let failureModes = row.hints.failureModes, !failureModes.isEmpty {
            parts.append("failure modes: \(failureModes.joined(separator: "; "))")
        }
        return parts.joined(separator: " | ")
    }

    private static func resourceURI(_ row: CatalogRow) -> String? {
        CapabilitySchemaBuilder.parseResourceMeta(row.capability.schemaJson)?.uri
    }

    private struct CatalogRow {
        let capability: CapabilityDef
        let compiled: CompiledSkill
        let hints: RoutingHints
    }

    private struct ScoredCatalogRow {
        let row: CatalogRow
        let score: Int
    }
}
