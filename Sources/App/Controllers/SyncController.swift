import Fluent
import Vapor

struct SyncController {
    static func trigger(req: Request) async throws -> Response {
        guard let account = req.storage[AccountKey.self], let account = account else {
            return Response(status: .unauthorized, body: .init(string: "{\"error\":\"Not authenticated\"}"))
        }

        let projectSlug = Environment.get("PROJECT_SLUG") ?? "default"
        let project = try await Project.query(on: req.db)
            .filter(\.$slug == projectSlug)
            .filter(\.$account.$id == account.id!)
            .first()

        guard let project = project else {
            return Response(status: .notFound, body: .init(string: "{\"error\":\"Project not found\"}"))
        }

        let pipeline = SyncPipeline(db: req.db, app: req.application)
        try await pipeline.run(projectId: project.id!)

        return Response(status: .ok, body: .init(string: "{\"ok\":true,\"message\":\"Sync completed\"}"))
    }
}
