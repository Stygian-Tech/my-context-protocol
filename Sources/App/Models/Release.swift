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

    @Children(for: \.$release)
    var skillPackages: [SkillPackage]

    init() {}

    init(
        id: UUID? = nil,
        projectId: UUID,
        commitSha: String,
        status: String,
        errorSummary: String? = nil
    ) {
        self.id = id
        self.$project.id = projectId
        self.commitSha = commitSha
        self.status = status
        self.errorSummary = errorSummary
    }
}
