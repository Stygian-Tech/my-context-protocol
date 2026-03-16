import Fluent
import Vapor

struct SessionAuthMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard let accountIdString = request.session.data["accountId"],
              let accountId = UUID(uuidString: accountIdString) else {
            return Response(status: .unauthorized, body: .init(string: "{\"error\":\"Not authenticated\"}"))
        }

        let account = try await Account.find(accountId, on: request.db)
        guard account != nil else {
            request.session.destroy()
            return Response(status: .unauthorized, body: .init(string: "{\"error\":\"Invalid session\"}"))
        }

        request.storage[AccountKey.self] = account
        return try await next.respond(to: request)
    }
}

struct AccountKey: StorageKey {
    typealias Value = Account?
}
