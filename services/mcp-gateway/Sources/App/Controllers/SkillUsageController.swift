import Fluent
import Vapor

enum SkillUsageController {
    static func index(req: Request) async throws -> SkillUsageResponse {
        guard let storedAccount = req.storage[AccountKey.self], let account = storedAccount, let accountId = account.id else { throw Abort(.unauthorized) }
        guard let projectId = req.parameters.get("id", as: UUID.self) else { throw Abort(.badRequest, reason: "Invalid project ID") }
        guard let project = try await Project.query(on: req.db).filter(\.$id == projectId).filter(\.$account.$id == accountId).first() else { throw Abort(.notFound) }
        return try await SkillUsageAnalyticsService.read(project: project, query: req.query.decode(SkillUsageQuery.self), db: req.db)
    }
}
