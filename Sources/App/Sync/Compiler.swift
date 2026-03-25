import Fluent
import Foundation
import Vapor

struct Compiler {
    let db: Database

    /// Compiles skill packages into compiled_skills, routing_rules, and capability_defs.
    func compile(
        releaseId: UUID,
        skills: [(parsed: ParsedSkill, package: SkillPackage)]
    ) async throws {
        for (parsed, package) in skills {
            let exposureType = SkillInference.inferExposureType(from: parsed)
            let sideEffectLevel = SkillInference.inferSideEffectLevel(from: parsed)
            let riskLevel = SkillInference.inferRiskLevel(from: parsed)
            let repoSpecific = SkillInference.inferRepoSpecific(from: parsed)
            let summary = parsed.description ?? String(parsed.body.prefix(200))
            let status = SkillInference.inferPublishabilityStatus(
                exposureType: exposureType,
                riskLevel: riskLevel,
                hasDescription: parsed.description != nil && !parsed.description!.isEmpty
            )

            let compiledSkill = CompiledSkill(
                releaseId: releaseId,
                skillPackageId: package.id!,
                path: package.path,
                name: package.name,
                summary: summary,
                skillBody: parsed.body,
                exposureType: exposureType,
                riskLevel: riskLevel,
                repoSpecific: repoSpecific,
                status: status
            )
            try await compiledSkill.save(on: db)

            let useWhenJson = parsed.useWhen.flatMap { (try? JSONEncoder().encode($0)).flatMap { String(data: $0, encoding: .utf8) } }
            let avoidWhenJson = parsed.avoidWhen.flatMap { (try? JSONEncoder().encode($0)).flatMap { String(data: $0, encoding: .utf8) } }
            let rule = RoutingRule(
                compiledSkillId: compiledSkill.id!,
                useWhenJson: useWhenJson,
                avoidWhenJson: avoidWhenJson
            )
            try await rule.save(on: db)

            let capabilityName = "skill:\(package.name)"
            let capabilityType = exposureType == "guidance" ? "prompt" : exposureType
            let schemaJson: String?
            switch capabilityType {
            case "tool":
                schemaJson = CapabilitySchemaBuilder.toolInputSchemaJson(
                    description: parsed.description,
                    summary: summary
                )
            case "resource":
                schemaJson = CapabilitySchemaBuilder.resourceMetaJson(skillName: package.name)
            case "prompt":
                schemaJson = CapabilitySchemaBuilder.promptMetaJson()
            default:
                schemaJson = CapabilitySchemaBuilder.toolInputSchemaJson(
                    description: parsed.description,
                    summary: summary
                )
            }
            let capDef = CapabilityDef(
                compiledSkillId: compiledSkill.id!,
                capabilityName: capabilityName,
                type: capabilityType,
                schemaJson: schemaJson,
                sideEffectLevel: sideEffectLevel
            )
            try await capDef.save(on: db)
        }
    }

    /// Recomputes `schema_json` when a compiled skill's exposure type is changed via the API.
    static func schemaJson(forCapabilityType capabilityType: String, compiled: CompiledSkill) -> String? {
        let summary = compiled.summary
        switch capabilityType {
        case "tool":
            return CapabilitySchemaBuilder.toolInputSchemaJson(description: nil, summary: summary)
        case "resource":
            return CapabilitySchemaBuilder.resourceMetaJson(skillName: compiled.name)
        case "prompt":
            return CapabilitySchemaBuilder.promptMetaJson()
        default:
            return CapabilitySchemaBuilder.toolInputSchemaJson(description: nil, summary: summary)
        }
    }
}
