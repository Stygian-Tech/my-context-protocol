import Fluent
import Vapor

final class CompiledSkill: Model, Content {
    static let schema = "compiled_skills"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "release_id")
    var release: Release

    @Parent(key: "skill_package_id")
    var skillPackage: SkillPackage

    @Field(key: "path")
    var path: String

    @Field(key: "name")
    var name: String

    @OptionalField(key: "summary")
    var summary: String?

    /// Full SKILL.md body (markdown) at compile time — used for MCP resources/prompts and rich tool responses.
    @OptionalField(key: "skill_body")
    var skillBody: String?

    @Field(key: "exposure_type")
    var exposureType: String

    @Field(key: "risk_level")
    var riskLevel: String

    @Field(key: "repo_specific")
    var repoSpecific: Bool

    @Field(key: "status")
    var status: String

    /// Whether the ingested SKILL.md included a closed YAML `---` front matter block.
    @Field(key: "yaml_frontmatter_present")
    var yamlFrontmatterPresent: Bool

    @Field(key: "canonical_schema_version") var canonicalSchemaVersion: Int
    @OptionalField(key: "skill_id") var skillId: String?
    @OptionalField(key: "kind") var kind: String?
    @OptionalField(key: "scope") var scope: String?
    @OptionalField(key: "activation_mode") var activationMode: String?
    @OptionalField(key: "enforcement") var enforcement: String?
    @OptionalField(key: "priority") var priority: Int?
    @OptionalField(key: "version") var version: String?
    @OptionalField(key: "source_checksum") var sourceChecksum: String?
    @OptionalField(key: "source_policy_json") var sourcePolicyJson: String?
    @OptionalField(key: "source_policy_base_checksum") var sourcePolicyBaseChecksum: String?
    @Field(key: "source_policy_stale") var sourcePolicyStale: Bool
    @OptionalField(key: "canonical_json") var canonicalJson: String?
    @OptionalField(key: "clarification_json") var clarificationJson: String?
    @Field(key: "clarification_required") var clarificationRequired: Bool

    /// Unified line diff vs `body_diff_prior_release_id` when SKILL body changed between releases.
    @OptionalField(key: "body_diff_unified")
    var bodyDiffUnified: String?

    @OptionalField(key: "body_diff_prior_release_id")
    var bodyDiffPriorReleaseId: UUID?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Children(for: \.$compiledSkill)
    var routingRules: [RoutingRule]

    @Children(for: \.$compiledSkill)
    var capabilityDefs: [CapabilityDef]

    init() {}

    init(
        id: UUID? = nil,
        releaseId: UUID,
        skillPackageId: UUID,
        path: String,
        name: String,
        summary: String? = nil,
        skillBody: String? = nil,
        exposureType: String,
        riskLevel: String,
        repoSpecific: Bool,
        status: String,
        yamlFrontmatterPresent: Bool = true,
        bodyDiffUnified: String? = nil,
        bodyDiffPriorReleaseId: UUID? = nil
    ) {
        self.id = id
        self.$release.id = releaseId
        self.$skillPackage.id = skillPackageId
        self.path = path
        self.name = name
        self.summary = summary
        self.skillBody = skillBody
        self.exposureType = exposureType
        self.riskLevel = riskLevel
        self.repoSpecific = repoSpecific
        self.status = status
        self.yamlFrontmatterPresent = yamlFrontmatterPresent
        self.canonicalSchemaVersion = CompiledSkillDocument.currentSchemaVersion
        self.clarificationRequired = true
        self.sourcePolicyStale = false
        self.bodyDiffUnified = bodyDiffUnified
        self.bodyDiffPriorReleaseId = bodyDiffPriorReleaseId
    }
}

extension CompiledSkill: @unchecked Sendable {}
