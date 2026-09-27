import Fluent
import Foundation
import Vapor

struct Compiler {
    let db: Database

    /// Compiles skill packages into compiled_skills, routing_rules, and capability_defs.
    func compile(
        releaseId: UUID,
        skills: [(parsed: ParsedSkill, package: SkillPackage)],
        sourcePolicies: [String: SkillSourcePolicyState] = [:]
    ) async throws {
        let release = try await Release.find(releaseId, on: db)
        let projectId = release?.$project.id
        let connection: RepoConnection? = if let projectId {
            try await RepoConnection.query(on: db).filter(\.$project.$id == projectId).first()
        } else { nil }
        for (parsed, package) in skills {
            let sourcePolicyState = sourcePolicies[package.name]
            let sourcePolicyStale = sourcePolicyState?.policy.baseChecksum.map { $0 != parsed.hash } ?? false
            let sourcePolicy = sourcePolicyStale ? nil : sourcePolicyState?.policy
            let overrideRow: SkillRuntimeOverride?
            if let projectId {
                let candidates = try await SkillRuntimeOverride.query(on: db)
                    .filter(\.$project.$id == projectId)
                    .filter(\.$skillId == package.name)
                    .all()
                overrideRow = Self.selectOverride(
                    from: candidates,
                    repoConnectionId: connection?.id,
                    preferredScope: sourcePolicy?.metadata.scope ?? parsed.scope ?? .task
                )
            } else {
                overrideRow = nil
            }
            let overrideBaseChecksum = overrideRow?.baseChecksum ?? overrideRow?.sourceChecksum
            let overrideStale = overrideBaseChecksum.map { $0 != parsed.hash } ?? false
            if let overrideRow, overrideRow.isStale != overrideStale {
                overrideRow.isStale = overrideStale
                try await overrideRow.save(on: db)
            }
            let overridePatch = overrideStale ? nil : SkillRuntimeJSON.decode(SkillRuntimeOverridePatch.self, from: overrideRow?.metadataJson)
            // Standard Agent Skills are guidance resources unless they explicitly opt into an
            // executable exposure. This avoids manufacturing callable tools from documentation.
            let exposureType = Self.exposureType(
                for: parsed,
                policyExposure: overridePatch?.exposure ?? sourcePolicy?.metadata.exposure
            )
            let effectiveUseWhen = overridePatch?.activation?.intents ?? sourcePolicy?.metadata.activation?.intents ?? parsed.useWhen
            let effectiveAvoidWhen = overridePatch?.avoidWhen ?? sourcePolicy?.metadata.avoidWhen ?? parsed.avoidWhen
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

            let capabilityName = MCPConstants.compiledCapabilityWireName(skillSlug: package.name)
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
                    useWhen: effectiveUseWhen,
                    avoidWhen: effectiveAvoidWhen,
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

            let routingHints = RoutingHints(
                useWhen: effectiveUseWhen,
                avoidWhen: effectiveAvoidWhen,
                failureModes: parsed.failureModes,
                invokeFirst: parsed.invokeFirst
            )
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
            let canonical = SkillCanonicalCompiler.compile(
                parsed: parsed,
                package: package,
                repository: connection.map { "\($0.repoOwner)/\($0.repoName)" },
                revision: release?.commitSha == "pending" ? parsed.hash : release?.commitSha,
                sourcePolicy: sourcePolicy,
                override: overridePatch
            )
            compiledSkill.skillId = canonical.document.id
            compiledSkill.kind = canonical.document.kind.rawValue
            compiledSkill.scope = canonical.document.scope.rawValue
            compiledSkill.activationMode = canonical.document.activation.mode.rawValue
            compiledSkill.enforcement = canonical.document.enforcement.rawValue
            compiledSkill.priority = canonical.document.priority
            compiledSkill.version = canonical.document.version
            compiledSkill.sourceChecksum = canonical.document.source.checksum
            compiledSkill.sourcePolicyJson = sourcePolicyState?.rawJson
            compiledSkill.sourcePolicyBaseChecksum = sourcePolicyState?.policy.baseChecksum
            compiledSkill.sourcePolicyStale = sourcePolicyStale
            compiledSkill.canonicalJson = SkillRuntimeJSON.encode(canonical.document)
            compiledSkill.clarificationJson = SkillRuntimeJSON.encode(canonical.questions)
            compiledSkill.clarificationRequired = canonical.document.validation.clarificationRequired
            try await compiledSkill.save(on: db)

            let useWhenJson = effectiveUseWhen.flatMap { (try? JSONEncoder().encode($0)).flatMap { String(data: $0, encoding: .utf8) } }
            let avoidWhenJson = effectiveAvoidWhen.flatMap { (try? JSONEncoder().encode($0)).flatMap { String(data: $0, encoding: .utf8) } }
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

    static func exposureType(for parsed: ParsedSkill, policyExposure: String? = nil) -> String {
        if let policyExposure {
            let normalized = policyExposure.lowercased()
            if ["tool", "resource", "prompt"].contains(normalized) { return normalized }
        }
        return parsed.exposeAs == nil ? "resource" : SkillInference.inferExposureType(from: parsed)
    }

    /// Tenant overrides may be project-wide (`repo_connection_id = NULL`) or tied to the
    /// repository currently being compiled. Ignore overrides owned by another repository,
    /// prefer the current repository over the project fallback, then choose the override whose
    /// declared scope matches the source policy. Remaining ties are stable across database plans.
    static func selectOverride(
        from rows: [SkillRuntimeOverride],
        repoConnectionId: UUID?,
        preferredScope: SkillScope
    ) -> SkillRuntimeOverride? {
        let eligible = rows.filter { row in
            guard let candidateRepoId = row.$repoConnection.id else { return true }
            return candidateRepoId == repoConnectionId
        }
        let scopeOrder: [String: Int] = [
            SkillScope.task.rawValue: 0,
            SkillScope.repository.rawValue: 1,
            SkillScope.workspace.rawValue: 2,
            SkillScope.organization.rawValue: 3,
            SkillScope.global.rawValue: 4
        ]
        return eligible.sorted { lhs, rhs in
            let lhsRepoRank = lhs.$repoConnection.id == repoConnectionId && repoConnectionId != nil ? 0 : 1
            let rhsRepoRank = rhs.$repoConnection.id == repoConnectionId && repoConnectionId != nil ? 0 : 1
            if lhsRepoRank != rhsRepoRank { return lhsRepoRank < rhsRepoRank }
            let lhsScopeRank = lhs.scope == preferredScope.rawValue ? -1 : (scopeOrder[lhs.scope] ?? 99)
            let rhsScopeRank = rhs.scope == preferredScope.rawValue ? -1 : (scopeOrder[rhs.scope] ?? 99)
            if lhsScopeRank != rhsScopeRank { return lhsScopeRank < rhsScopeRank }
            let lhsUpdated = lhs.updatedAt ?? .distantPast
            let rhsUpdated = rhs.updatedAt ?? .distantPast
            if lhsUpdated != rhsUpdated { return lhsUpdated > rhsUpdated }
            return (lhs.id?.uuidString ?? "") < (rhs.id?.uuidString ?? "")
        }.first
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
