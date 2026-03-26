import Fluent
import Foundation
import Vapor

/// After a new release is compiled, merge dashboard edits and routing/schema from the prior active release
/// onto matching compiled skills, and record unified diffs when SKILL bodies changed.
enum ReleaseMetadataCarryForward {
    static func apply(
        db: Database,
        newReleaseId: UUID,
        priorReleaseId: UUID?
    ) async throws -> Int {
        guard let priorId = priorReleaseId, priorId != newReleaseId else { return 0 }

        let oldSkills = try await CompiledSkill.query(on: db)
            .filter(\.$release.$id == priorId)
            .with(\.$routingRules)
            .with(\.$capabilityDefs)
            .all()

        var oldByKey: [String: CompiledSkill] = [:]
        oldByKey.reserveCapacity(oldSkills.count)
        for cs in oldSkills {
            oldByKey[key(cs)] = cs
        }

        let newSkills = try await CompiledSkill.query(on: db)
            .filter(\.$release.$id == newReleaseId)
            .with(\.$routingRules)
            .with(\.$capabilityDefs)
            .all()

        var changeCount = 0

        for newCS in newSkills {
            guard let oldCS = oldByKey[key(newCS)] else { continue }

            let oldBody = oldCS.skillBody ?? ""
            let newBody = newCS.skillBody ?? ""
            if let diff = SkillBodyUnifiedDiff.format(oldText: oldBody, newText: newBody) {
                newCS.bodyDiffUnified = diff
                newCS.bodyDiffPriorReleaseId = priorId
                changeCount += 1
            }

            newCS.summary = oldCS.summary
            newCS.riskLevel = oldCS.riskLevel
            newCS.status = oldCS.status
            newCS.repoSpecific = oldCS.repoSpecific

            try await newCS.save(on: db)

            if let oldRule = oldCS.routingRules.first {
                let newRule: RoutingRule
                if let existing = newCS.routingRules.first {
                    newRule = existing
                } else {
                    newRule = RoutingRule(compiledSkillId: newCS.id!)
                    try await newRule.save(on: db)
                }
                newRule.useWhenJson = oldRule.useWhenJson
                newRule.avoidWhenJson = oldRule.avoidWhenJson
                newRule.failureModesJson = oldRule.failureModesJson
                newRule.invokeFirst = oldRule.invokeFirst
                try await newRule.save(on: db)
            }

            let capType = newCS.exposureType == "guidance" ? "prompt" : newCS.exposureType
            if let oldCap = oldCS.capabilityDefs.first, let newCap = newCS.capabilityDefs.first {
                newCap.capabilityName = "skill:\(newCS.name)"
                newCap.type = capType
                newCap.schemaJson = oldCap.schemaJson
                newCap.sideEffectLevel = oldCap.sideEffectLevel
                try await newCap.save(on: db)
            }
        }

        return changeCount
    }

    private static func key(_ cs: CompiledSkill) -> String {
        "\(cs.path)\u{0}\(cs.name)\u{0}\(cs.exposureType)"
    }
}
