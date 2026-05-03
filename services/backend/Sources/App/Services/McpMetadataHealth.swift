import Foundation
import Fluent

/// Dashboard-only MCP metadata quality (mirrors frontend `metadataHealthTier` in `release-skill-metadata-dialog.tsx`).
enum McpMetadataHealth {
    enum Tier: Equatable {
        case blocking
        case warning
        case ok
    }

    /// MCP metadata quality ignoring `compiled.status` — used to infer publish status at compile / PATCH time.
    static func metadataOnlyTier(
        exposureType: String,
        yamlFrontmatterPresent: Bool,
        skillBody: String?,
        schemaJson: String?,
        routing: RoutingHints
    ) -> Tier {
        let raw = schemaJson?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !raw.isEmpty {
            guard (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) != nil else {
                return .blocking
            }
        }
        if exposureType == "resource" {
            if raw.isEmpty {
                return .blocking
            }
            guard let data = raw.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let uri = obj["uri"] as? String,
                  !uri.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .blocking
            }
        }
        if !yamlFrontmatterPresent {
            return .warning
        }
        let body = skillBody?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if body.isEmpty {
            return .warning
        }
        if exposureType == "resource" {
            let uw = routing.useWhen ?? []
            let aw = routing.avoidWhen ?? []
            let fm = routing.failureModes ?? []
            if uw.isEmpty && aw.isEmpty && fm.isEmpty {
                return .warning
            }
        }
        return .ok
    }

    /// Combine SKILL inference with metadata tier: blocking → `not_publishable`, warning → `needs_review` unless already not publishable, ok → `inferred`.
    static func resolvedPublishStatus(inferred: String, metadataTier: Tier) -> String {
        switch metadataTier {
        case .blocking:
            return "not_publishable"
        case .warning:
            return inferred == "not_publishable" ? "not_publishable" : "needs_review"
        case .ok:
            return inferred
        }
    }

    static func tier(
        compiled: CompiledSkill,
        schemaJson: String?,
        routing: RoutingHints
    ) -> Tier {
        if compiled.status == "not_publishable" {
            return .blocking
        }
        let meta = metadataOnlyTier(
            exposureType: compiled.exposureType,
            yamlFrontmatterPresent: compiled.yamlFrontmatterPresent,
            skillBody: compiled.skillBody,
            schemaJson: schemaJson,
            routing: routing
        )
        if meta == .blocking {
            return .blocking
        }
        if compiled.status == "needs_review" {
            return .warning
        }
        if meta == .warning {
            return .warning
        }
        if compiled.status == "ready" {
            return .ok
        }
        return .warning
    }

    /// Per-release counts of compiled skills by tier (for release list API).
    static func blockingAndWarningCountsByRelease(
        releaseIds: [UUID],
        compiledSkills: [CompiledSkill],
        schemaBySkillId: [UUID: String],
        ruleBySkillId: [UUID: RoutingRule]
    ) -> [UUID: (blocking: Int, warning: Int)] {
        var blocking: [UUID: Int] = [:]
        var warning: [UUID: Int] = [:]
        for id in releaseIds {
            blocking[id] = 0
            warning[id] = 0
        }
        for cs in compiledSkills {
            let rid = cs.$release.id
            guard let sid = cs.id, releaseIds.contains(rid) else { continue }
            let schema = schemaBySkillId[sid]
            let hints = RoutingHints.from(rule: ruleBySkillId[sid])
            switch tier(compiled: cs, schemaJson: schema, routing: hints) {
            case .blocking:
                blocking[rid] = (blocking[rid] ?? 0) + 1
            case .warning:
                warning[rid] = (warning[rid] ?? 0) + 1
            case .ok:
                break
            }
        }
        var out: [UUID: (blocking: Int, warning: Int)] = [:]
        for id in releaseIds {
            out[id] = (blocking[id] ?? 0, warning[id] ?? 0)
        }
        return out
    }
}
