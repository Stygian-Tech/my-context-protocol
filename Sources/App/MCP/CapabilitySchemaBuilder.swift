import Foundation

/// Builds `schema_json` for `CapabilityDef` rows and stable resource URIs for MCP.
///
/// Contract:
/// - **tool**: JSON string of an MCP-compatible `inputSchema` object (`type`, `properties`, optional `required`).
/// - **resource**: JSON object `{ "uri": "ctx://skill/...", "mimeType": "text/markdown" }` for `resources/list` / `resources/read`.
/// - **prompt**: JSON object `{ "arguments": [] }` (reserved; prompt params can be extended later).
enum CapabilitySchemaBuilder {
    static let resourceURIScheme = "ctx"
    static let resourceURIHost = "skill"

    static func toolInputSchemaJson(description: String?, summary: String?) -> String {
        let blurb = [description, summary].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        let detailHelp: String
        if let blurb, !blurb.isEmpty {
            detailHelp = "Optional extra context. Skill summary: \(blurb)"
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
        let uri = resourceURI(skillName: skillName)
        let payload: [String: String] = [
            "uri": uri,
            "mimeType": "text/markdown"
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
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

    static func parseResourceMeta(_ schemaJson: String?) -> (uri: String, mimeType: String)? {
        guard let schemaJson, let data = schemaJson.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let uri = obj["uri"] as? String, !uri.isEmpty else {
            return nil
        }
        let mime = (obj["mimeType"] as? String) ?? "text/markdown"
        return (uri, mime)
    }
}
