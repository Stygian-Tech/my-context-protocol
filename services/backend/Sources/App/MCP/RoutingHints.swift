import Foundation

/// Decoded agent-routing fields persisted on `RoutingRule` and mirrored into MCP resource `schema_json`.
struct RoutingHints: Equatable {
    let useWhen: [String]?
    let avoidWhen: [String]?
    let failureModes: [String]?
    let invokeFirst: Bool?

    static let empty = RoutingHints(useWhen: nil, avoidWhen: nil, failureModes: nil, invokeFirst: nil)

    /// Routing fields from parsed SKILL.md before a `RoutingRule` row exists (compile pipeline).
    static func from(parsed: ParsedSkill) -> RoutingHints {
        RoutingHints(
            useWhen: parsed.useWhen,
            avoidWhen: parsed.avoidWhen,
            failureModes: parsed.failureModes,
            invokeFirst: parsed.invokeFirst
        )
    }

    static func from(rule: RoutingRule?) -> RoutingHints {
        guard let rule else {
            return RoutingHints(useWhen: nil, avoidWhen: nil, failureModes: nil, invokeFirst: nil)
        }
        let useWhen = decodeStringArray(rule.useWhenJson)
        let avoidWhen = decodeStringArray(rule.avoidWhenJson)
        let failureModes = decodeStringArray(rule.failureModesJson)
        let invoke = rule.invokeFirst
        return RoutingHints(
            useWhen: useWhen,
            avoidWhen: avoidWhen,
            failureModes: failureModes,
            invokeFirst: invoke
        )
    }

    private static func decodeStringArray(_ raw: String?) -> [String]? {
        guard let raw, let data = raw.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data), !arr.isEmpty else {
            return nil
        }
        return arr
    }

    var hasAnyAgentMetadata: Bool {
        if invokeFirst == true { return true }
        if let u = useWhen, !u.isEmpty { return true }
        if let a = avoidWhen, !a.isEmpty { return true }
        if let f = failureModes, !f.isEmpty { return true }
        return false
    }
}
