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
            let summary = parsed.description.map { d in
                d.count > 2048 ? String(d.prefix(2048)) : d
            } ?? String(parsed.body.prefix(200))
            let inferredStatus = SkillInference.inferPublishabilityStatus(
                exposureType: exposureType,
                riskLevel: riskLevel,
                hasDescription: parsed.description != nil && !parsed.description!.isEmpty
            )

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
                schemaJson = CapabilitySchemaBuilder.resourceMetaJson(
                    skillName: package.name,
                    useWhen: parsed.useWhen,
                    avoidWhen: parsed.avoidWhen,
                    failureModes: parsed.failureModes,
                    invokeFirst: parsed.invokeFirst
                )
            case "prompt":
                schemaJson = CapabilitySchemaBuilder.promptMetaJson()
            default:
                schemaJson = CapabilitySchemaBuilder.toolInputSchemaJson(
                    description: parsed.description,
                    summary: summary
                )
            }

            let routingHints = RoutingHints.from(parsed: parsed)
            let metadataTier = McpMetadataHealth.metadataOnlyTier(
                exposureType: exposureType,
                yamlFrontmatterPresent: parsed.hadYamlFrontmatter,
                skillBody: parsed.body,
                schemaJson: schemaJson,
                routing: routingHints
            )
            let status = McpMetadataHealth.resolvedPublishStatus(
                inferred: inferredStatus,
                metadataTier: metadataTier
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
                status: status,
                yamlFrontmatterPresent: parsed.hadYamlFrontmatter
            )
            try await compiledSkill.save(on: db)

            let useWhenJson = parsed.useWhen.flatMap { (try? JSONEncoder().encode($0)).flatMap { String(data: $0, encoding: .utf8) } }
            let avoidWhenJson = parsed.avoidWhen.flatMap { (try? JSONEncoder().encode($0)).flatMap { String(data: $0, encoding: .utf8) } }
            let failureModesJson = parsed.failureModes.flatMap { (try? JSONEncoder().encode($0)).flatMap { String(data: $0, encoding: .utf8) } }
            let rule = RoutingRule(
                compiledSkillId: compiledSkill.id!,
                useWhenJson: useWhenJson,
                avoidWhenJson: avoidWhenJson,
                failureModesJson: failureModesJson,
                invokeFirst: parsed.invokeFirst
            )
            try await rule.save(on: db)
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
    static func schemaJson(
        forCapabilityType capabilityType: String,
        compiled: CompiledSkill,
        routingHints: RoutingHints = .empty
    ) -> String? {
        let summary = compiled.summary
        switch capabilityType {
        case "tool":
            return CapabilitySchemaBuilder.toolInputSchemaJson(description: nil, summary: summary)
        case "resource":
            return CapabilitySchemaBuilder.resourceMetaJson(
                skillName: compiled.name,
                useWhen: routingHints.useWhen,
                avoidWhen: routingHints.avoidWhen,
                failureModes: routingHints.failureModes,
                invokeFirst: routingHints.invokeFirst
            )
        case "prompt":
            return CapabilitySchemaBuilder.promptMetaJson()
        default:
            return CapabilitySchemaBuilder.toolInputSchemaJson(description: nil, summary: summary)
        }
    }
}
