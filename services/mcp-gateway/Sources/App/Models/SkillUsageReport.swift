import Fluent
import Vapor

/// Stores only a normalized payload digest, never agent text or task content.
final class SkillUsageReport: Model, @unchecked Sendable {
    static let schema = "skill_usage_reports"
    @ID(key: .id) var id: UUID?
    @Parent(key: "project_id") var project: Project
    @Field(key: "client_identity") var clientIdentity: String
    @Field(key: "report_id") var reportId: String
    @Field(key: "payload_hash") var payloadHash: String
    @Field(key: "recorded_count") var recordedCount: Int
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    init() {}
}
