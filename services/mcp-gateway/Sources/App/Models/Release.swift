import Fluent
import Vapor

final class Release: Model, Content {
    static let schema = "releases"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "project_id")
    var project: Project

    @Field(key: "commit_sha")
    var commitSha: String

    @Field(key: "status")
    var status: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @OptionalField(key: "error_summary")
    var errorSummary: String?

    /// Number of compiled skills whose `body_diff_unified` is set for this release.
    @Field(key: "skill_body_changes_count")
    var skillBodyChangesCount: Int

    @Children(for: \.$release)
    var skillPackages: [SkillPackage]

    @Children(for: \.$release)
    var compiledSkills: [CompiledSkill]

    @Children(for: \.$release)
    var validationReportRecords: [ValidationReportRecord]

    init() {}

    init(
        id: UUID? = nil,
        projectId: UUID,
        commitSha: String,
        status: String,
        errorSummary: String? = nil,
        skillBodyChangesCount: Int = 0
    ) {
        self.id = id
        self.$project.id = projectId
        self.commitSha = commitSha
        self.status = status
        self.errorSummary = errorSummary
        self.skillBodyChangesCount = skillBodyChangesCount
    }
}

extension Release: @unchecked Sendable {}
