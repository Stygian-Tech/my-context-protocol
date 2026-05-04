import Foundation

/// Infers exposure_type and side_effect_level from skill content when not in frontmatter.
enum SkillInference {
    static func inferExposureType(from skill: ParsedSkill) -> String {
        if let exposeAs = skill.exposeAs, !exposeAs.isEmpty {
            let lower = exposeAs.lowercased()
            if lower == "tool" || lower == "resource" || lower == "prompt" || lower == "guidance" {
                return lower == "guidance" ? "prompt" : lower
            }
        }
        return "tool"
    }

    static func inferSideEffectLevel(from skill: ParsedSkill) -> String {
        if let sideEffects = skill.sideEffects, !sideEffects.isEmpty {
            let lower = sideEffects.lowercased()
            if ["none", "read", "mutating", "destructive"].contains(lower) {
                return lower
            }
        }
        return "none"
    }

    static func inferRiskLevel(from skill: ParsedSkill) -> String {
        if let risk = skill.riskLevel, !risk.isEmpty {
            let lower = risk.lowercased()
            if ["low", "medium", "high"].contains(lower) {
                return lower
            }
        }
        return "low"
    }

    static func inferRepoSpecific(from skill: ParsedSkill) -> Bool {
        skill.repoSpecific ?? false
    }

    static func inferPublishabilityStatus(
        exposureType: String,
        riskLevel: String,
        hasDescription: Bool
    ) -> String {
        guard hasDescription else { return "not_publishable" }
        if riskLevel == "high" { return "needs_review" }
        return "ready"
    }
}
