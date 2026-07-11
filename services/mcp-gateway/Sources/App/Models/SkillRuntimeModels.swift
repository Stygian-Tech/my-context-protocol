import Fluent
import Vapor

final class SkillRuntimeOverride: Model, Content, @unchecked Sendable {
    static let schema = "skill_runtime_overrides"
    @ID(key: .id) var id: UUID?
    @Parent(key: "project_id") var project: Project
    @OptionalParent(key: "repo_connection_id") var repoConnection: RepoConnection?
    @Field(key: "skill_id") var skillId: String
    @Field(key: "scope") var scope: String
    @Field(key: "metadata_json") var metadataJson: String
    @OptionalField(key: "source_checksum") var sourceChecksum: String?
    @OptionalField(key: "writeback_pr_url") var writebackPrUrl: String?
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?
    init() {}
}

final class SkillAssignment: Model, Content, @unchecked Sendable {
    static let schema = "skill_assignments"
    @ID(key: .id) var id: UUID?
    @Parent(key: "project_id") var project: Project
    @OptionalParent(key: "repo_connection_id") var repoConnection: RepoConnection?
    @Field(key: "skill_id") var skillId: String
    @Field(key: "scope") var scope: String
    @Field(key: "activation_mode") var activationMode: String
    @Field(key: "required") var required: Bool
    @Field(key: "priority") var priority: Int
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    init() {}
}

final class ProjectRuntimeSettings: Model, Content, @unchecked Sendable {
    static let schema = "project_runtime_settings"
    @ID(key: .id) var id: UUID?
    @Parent(key: "project_id") var project: Project
    @Field(key: "telemetry_enabled") var telemetryEnabled: Bool
    @Field(key: "telemetry_retention_days") var telemetryRetentionDays: Int
    @Field(key: "semantic_enabled") var semanticEnabled: Bool
    @OptionalField(key: "embedding_provider") var embeddingProvider: String?
    @OptionalField(key: "embedding_model") var embeddingModel: String?
    @Field(key: "feedback_issue_creation_enabled") var feedbackIssueCreationEnabled: Bool
    @OptionalField(key: "provider_preferences_json") var providerPreferencesJson: String?
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?
    init() {}
}

final class SkillFeedbackRecord: Model, Content, @unchecked Sendable {
    static let schema = "skill_feedback"
    @ID(key: .id) var id: UUID?
    @Parent(key: "project_id") var project: Project
    @Field(key: "skill_id") var skillId: String
    @Field(key: "skill_version") var skillVersion: String
    @Field(key: "source_path") var sourcePath: String
    @OptionalField(key: "source_revision") var sourceRevision: String?
    @Field(key: "category") var category: String
    @Field(key: "summary") var summary: String
    @OptionalField(key: "evidence") var evidence: String?
    @OptionalField(key: "suggested_change") var suggestedChange: String?
    @Field(key: "issue_draft_json") var issueDraftJson: String
    @OptionalField(key: "external_issue_url") var externalIssueUrl: String?
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    init() {}
}

final class SkillEmbeddingRecord: Model, Content, @unchecked Sendable {
    static let schema = "skill_embeddings"
    @ID(key: .id) var id: UUID?
    @Parent(key: "project_id") var project: Project
    @Field(key: "skill_id") var skillId: String
    @Field(key: "source_checksum") var sourceChecksum: String
    @Field(key: "provider") var provider: String
    @Field(key: "model") var model: String
    @Field(key: "vector_json") var vectorJson: String
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    init() {}
}

final class SkillRuntimeEvent: Model, Content, @unchecked Sendable {
    static let schema = "skill_runtime_events"
    @ID(key: .id) var id: UUID?
    @Parent(key: "project_id") var project: Project
    @Field(key: "trace_id") var traceId: UUID
    @Field(key: "event_type") var eventType: String
    @OptionalField(key: "skill_id") var skillId: String?
    @OptionalField(key: "reason_code") var reasonCode: String?
    @OptionalField(key: "score") var score: Double?
    @OptionalField(key: "request_hash") var requestHash: String?
    @Field(key: "detail_json") var detailJson: String
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    init() {}
}
