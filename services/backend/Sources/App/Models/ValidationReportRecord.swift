import Fluent
import Vapor

final class ValidationReportRecord: Model, Content {
    static let schema = "validation_reports"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "release_id")
    var release: Release

    @Field(key: "report_json")
    var reportJson: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        releaseId: UUID,
        reportJson: String
    ) {
        self.id = id
        self.$release.id = releaseId
        self.reportJson = reportJson
    }
}

extension ValidationReportRecord: @unchecked Sendable {}
