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
