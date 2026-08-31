import Foundation

/// Machine-readable resource row from `capability_defs.schema_json` for MCP resources.
struct ParsedResourceMeta: Equatable {
    let uri: String
    let mimeType: String
    let useWhen: [String]?
    let avoidWhen: [String]?
    let failureModes: [String]?
    let invokeFirst: Bool?
}

/// Builds `schema_json` for `CapabilityDef` rows and stable resource URIs for MCP.
///
/// Contract:
/// - **tool**: JSON string of an MCP-compatible `inputSchema` object (`type`, `properties`, optional `required`).
/// - **resource**: JSON object with `uri`, `mimeType`, and optional agent hints (`use_when`, `avoid_when`, `failure_modes`, `invoke_first`).
/// - **prompt**: JSON object `{ "arguments": [] }` (reserved; prompt params can be extended later).
enum CapabilitySchemaBuilder {
    static let resourceURIScheme = "ctx"
    static let resourceURIHost = "skill"

    static func toolInputSchemaJson(description: String?, summary: String?) -> String {
        let blurb = [description, summary].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        let detailHelp: String
        if let blurb, !blurb.isEmpty {
            let capped = blurb.count > 480 ? String(blurb.prefix(480)) + "…" : blurb
            detailHelp = "Optional extra context. Skill summary: \(capped)"
        } else {
            detailHelp = "Optional extra context or question for this skill."
        }
        let payload = ToolSchemaPayload(
            type: "object",
            properties: [
                "detail": .init(type: "string", description: detailHelp)
            ],
            additionalProperties: false
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        if let data = try? enc.encode(payload), let s = String(data: data, encoding: .utf8) {
            return s
        }
        return #"{"type":"object","properties":{}}"#
    }

    static func catalogToolInputSchemaJson() -> String {
        let payload = ToolSchemaPayload(
            type: "object",
            properties: [
                "mode": .init(
                    type: "string",
                    description: "Optional catalog mode: overview, route, or skill. Defaults to overview; task implies route and skill implies skill."
                ),
                "task": .init(
                    type: "string",
                    description: "Current user task. In route mode, the catalog ranks relevant skills and returns exact next MCP actions."
                ),
                "skill": .init(
                    type: "string",
                    description: "Skill slug, capability name, path, or ctx://skill/... URI. In skill mode, returns the full SKILL.md body."
                ),
                "limit": .init(
                    type: "string",
                    description: "Maximum route results to return. Defaults to 5."
                )
            ],
            additionalProperties: false
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        if let data = try? enc.encode(payload), let s = String(data: data, encoding: .utf8) {
            return s
        }
        return #"{"type":"object","properties":{}}"#
    }

    static func runtimeToolInputSchemaJson(name: String) -> String {
        (try? encoderString(runtimeToolInputSchema(name: name))) ?? #"{"type":"object","properties":{}}"#
    }

    static func runtimeToolInputSchema(name: String) -> InputSchema {
        switch name {
        case MCPConstants.resolveContextToolName:
            return InputSchema(
                type: "object",
                properties: [
                    "request": stringSchema("Current user request or task."),
                    "event": stringSchema("Optional canonical or freeform runtime event."),
                    "context": runtimeContextSchema(),
                    "user": stringSchema("Optional user identifier."),
                    "organization": stringSchema("Optional organization name."),
                    "workspace": stringSchema("Optional workspace name."),
                    "repository": stringSchema("Optional owner/repository identifier."),
                    "task": stringSchema("Optional stable task identifier for task-scoped assignments."),
                    "current_skill_ids": InputSchema(
                        type: "array",
                        description: "Stable IDs for skills already active in the agent session.",
                        items: InputSchema(type: "string", minLength: 1),
                        uniqueItems: true
                    ),
                    "available_tools": InputSchema(
                        type: "array",
                        description: "Provider-neutral inventory of tools currently available to the agent.",
                        items: runtimeToolInventoryItemSchema()
                    ),
                ],
                required: ["request"],
                additionalProperties: false
            )
        case MCPConstants.getSkillToolName:
            return InputSchema(
                type: "object",
                properties: [
                    "skill_id": stringSchema("Stable skill ID.", minLength: 1),
                    "version": stringSchema("Optional exact semantic version.", minLength: 1),
                    "path": stringSchema("Optional safe package-relative file path.", minLength: 1, maxLength: 1_024),
                ],
                required: ["skill_id"],
                additionalProperties: false
            )
        case MCPConstants.reportSkillFeedbackToolName:
            return InputSchema(
                type: "object",
                properties: [
                    "skill_id": stringSchema("Stable skill ID.", minLength: 1),
                    "version": stringSchema("Observed skill version.", minLength: 1),
                    "category": InputSchema(
                        type: "string",
                        description: "Feedback category.",
                        enumValues: [
                            "missing_guidance", "ambiguous_instruction", "incorrect_instruction", "conflict",
                            "missing_capability", "poor_discovery", "outdated_content", "other",
                        ].map(JSONValue.string)
                    ),
                    "summary": stringSchema("Concise problem summary.", minLength: 1, maxLength: 2_000),
                    "evidence": stringSchema("Reproducible evidence for the observed skill version.", minLength: 1, maxLength: 8_000),
                    "suggested_change": stringSchema("Optional suggested improvement.", maxLength: 8_000),
                    "create_issue": InputSchema(
                        type: "boolean",
                        description: "Request authorized external issue creation. The server still returns a draft for the harness to execute."
                    ),
                ],
                required: ["skill_id", "version", "category", "summary", "evidence"],
                additionalProperties: false
            )
        default:
            return InputSchema(type: "object", properties: [:], additionalProperties: false)
        }
    }

    static func runtimeToolOutputSchema(name: String) -> InputSchema {
        switch name {
        case MCPConstants.resolveContextToolName:
            return InputSchema(
                type: "object",
                properties: [
                    "schemaVersion": InputSchema(type: "integer", minimum: 1),
                    "traceId": InputSchema(type: "string", format: "uuid"),
                    "activeSkills": arrayOfObjectsSchema(),
                    "suggestedTaskSkills": arrayOfObjectsSchema(),
                    "capabilityBindings": arrayOfObjectsSchema(),
                    "missingRequirements": InputSchema(type: "array", items: InputSchema(type: "string")),
                    "conflicts": arrayOfObjectsSchema(),
                    "missingContext": InputSchema(type: "array", items: InputSchema(type: "string")),
                    "eventCanonical": InputSchema(type: "boolean"),
                    "nextActions": arrayOfObjectsSchema(),
                    "resolutionTrace": arrayOfObjectsSchema(),
                ],
                required: [
                    "schemaVersion", "traceId", "activeSkills", "suggestedTaskSkills", "capabilityBindings",
                    "missingRequirements", "conflicts", "missingContext", "nextActions", "resolutionTrace",
                ],
                additionalProperties: false
            )
        case MCPConstants.getSkillToolName:
            return InputSchema(
                type: "object",
                properties: [
                    "schemaVersion": InputSchema(type: "integer", minimum: 1),
                    "kind": InputSchema(type: "string", enumValues: [.string("skill"), .string("file")]),
                    "id": stringSchema("Stable skill ID."),
                    "version": stringSchema("Exact skill version."),
                    "checksum": stringSchema("SHA-256 content checksum."),
                    "mediaType": stringSchema("Resource media type."),
                    "resourceUri": stringSchema("Stable ctx resource URI."),
                    "source": InputSchema(type: "object", additionalProperties: true),
                ],
                required: ["schemaVersion", "kind", "id", "version", "checksum", "mediaType", "resourceUri", "source"],
                additionalProperties: true
            )
        case MCPConstants.reportSkillFeedbackToolName:
            return InputSchema(
                type: "object",
                properties: [
                    "schemaVersion": InputSchema(type: "integer", minimum: 1),
                    "feedbackId": InputSchema(type: "string", format: "uuid"),
                    "effectStatus": InputSchema(type: "string", enumValues: [.string("draft")]),
                    "issueDraft": InputSchema(type: "object", additionalProperties: true),
                    "creationAuthorized": InputSchema(type: "boolean"),
                    "message": InputSchema(type: "string"),
                ],
                required: ["schemaVersion", "feedbackId", "effectStatus", "issueDraft", "creationAuthorized", "message"],
                additionalProperties: false
            )
        default:
            return InputSchema(type: "object", properties: [:])
        }
    }

    private static func stringSchema(
        _ description: String,
        minLength: Int? = nil,
        maxLength: Int? = nil
    ) -> InputSchema {
        InputSchema(type: "string", description: description, minLength: minLength, maxLength: maxLength)
    }

    private static func runtimeContextSchema() -> InputSchema {
        InputSchema(
            type: "object",
            properties: [
                "user": stringSchema("Optional user identifier."),
                "organization": stringSchema("Optional organization name."),
                "workspace": stringSchema("Optional workspace name."),
                "repository": stringSchema("Optional owner/repository identifier."),
                "task": stringSchema("Optional stable task identifier for task-scoped assignments."),
            ],
            additionalProperties: false
        )
    }

    private static func runtimeToolInventoryItemSchema() -> InputSchema {
        InputSchema(
            type: "object",
            properties: [
                "server": stringSchema("MCP server name.", minLength: 1),
                "name": stringSchema("Tool name.", minLength: 1),
                "description": stringSchema("Optional tool description."),
                "inputSchema": stringSchema("Optional serialized tool input schema."),
                "provider": stringSchema("Optional provider name."),
            ],
            required: ["server", "name"],
            additionalProperties: false
        )
    }

    private static func arrayOfObjectsSchema() -> InputSchema {
        InputSchema(type: "array", items: InputSchema(type: "object", additionalProperties: true))
    }

    private static func encoderString<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return String(data: try encoder.encode(value), encoding: .utf8) ?? "{}"
    }

    private struct ToolSchemaPayload: Encodable {
        let type: String
        let properties: [String: Prop]
        let additionalProperties: Bool

        struct Prop: Encodable {
            let type: String
            let description: String?
        }
    }

    static func resourceMetaJson(skillName: String) -> String {
        resourceMetaJson(
            skillName: skillName,
            useWhen: nil,
            avoidWhen: nil,
            failureModes: nil,
            invokeFirst: nil
        )
    }

    /// Rich metadata for `resources/list`, `resources/read` preamble, and dashboard catalog.
    static func resourceMetaJson(
        skillName: String,
        useWhen: [String]?,
        avoidWhen: [String]?,
        failureModes: [String]?,
        invokeFirst: Bool?
    ) -> String {
        let uri = resourceURI(skillName: skillName)
        var payload: [String: Any] = [
            "uri": uri,
            "mimeType": "text/markdown"
        ]
        if let useWhen, !useWhen.isEmpty {
            payload["use_when"] = useWhen
        }
        if let avoidWhen, !avoidWhen.isEmpty {
            payload["avoid_when"] = avoidWhen
        }
        if let failureModes, !failureModes.isEmpty {
            payload["failure_modes"] = failureModes
        }
        if invokeFirst == true {
            payload["invoke_first"] = true
        }
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        return #"{"uri":"ctx://skill/","mimeType":"text/markdown"}"#
    }

    static func promptMetaJson() -> String {
        let payload: [[String: Any]] = []
        let o: [String: Any] = ["arguments": payload]
        if let data = try? JSONSerialization.data(withJSONObject: o, options: []),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        return "{}"
    }

    /// Stable URI for a skill resource, e.g. `ctx://skill/My%20Skill`.
    static func resourceURI(skillName: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let enc = skillName.addingPercentEncoding(withAllowedCharacters: allowed) ?? skillName
        return "\(resourceURIScheme)://\(resourceURIHost)/\(enc)"
    }

    /// Rewrites `uri` to match `skillName`, preserving other keys (for release carry-forward after renames or manual edits).
    static func resourceSchemaJsonWithPatchedUri(schemaJson: String, skillName: String) -> String? {
        guard let data = schemaJson.data(using: .utf8),
              var obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        obj["uri"] = resourceURI(skillName: skillName)
        guard let out = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
              let s = String(data: out, encoding: .utf8) else {
            return nil
        }
        return s
    }

    static func parseResourceMeta(_ schemaJson: String?) -> ParsedResourceMeta? {
        guard let schemaJson, let data = schemaJson.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let uri = obj["uri"] as? String, !uri.isEmpty else {
            return nil
        }
        let mime = (obj["mimeType"] as? String) ?? "text/markdown"
        let useWhen = obj["use_when"] as? [String]
        let avoidWhen = obj["avoid_when"] as? [String]
        let failureModes = obj["failure_modes"] as? [String]
        let invokeFirst = obj["invoke_first"] as? Bool
        return ParsedResourceMeta(
            uri: uri,
            mimeType: mime,
            useWhen: useWhen,
            avoidWhen: avoidWhen,
            failureModes: failureModes,
            invokeFirst: invokeFirst
        )
    }

    /// Short markdown block prepended to `resources/read` so agents see triggers without re-parsing SKILL frontmatter.
    static func resourceReadPreamble(meta: ParsedResourceMeta, skillSummary: String?) -> String? {
        var lines: [String] = []
        if meta.invokeFirst == true {
            lines.append("**Invoke first:** consider loading this resource before other skills on the same task.")
        }
        if let use = meta.useWhen, !use.isEmpty {
            lines.append("**Read when:**")
            for u in use {
                lines.append("- \(u)")
            }
        }
        if let avoid = meta.avoidWhen, !avoid.isEmpty {
            lines.append("**Skip when:**")
            for a in avoid {
                lines.append("- \(a)")
            }
        }
        if let fm = meta.failureModes, !fm.isEmpty {
            lines.append("**Failure modes / fallbacks:**")
            for f in fm {
                lines.append("- \(f)")
            }
        }
        guard !lines.isEmpty else {
            return nil
        }
        var out = "<!-- MyContextProtocol: agent routing (from SKILL front matter) -->\n\n"
        out += lines.joined(separator: "\n")
        out += "\n\n---\n\n"
        if let s = skillSummary?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            out += "*Summary:* \(s)\n\n---\n\n"
        }
        return out
    }
}
