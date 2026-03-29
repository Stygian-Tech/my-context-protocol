import Vapor

/// Requires an authenticated session and `Account.isAdmin == true`.
struct AdminAuthMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard let wrapped = request.storage[AccountKey.self], let account = wrapped else {
            return jsonError(status: .unauthorized, message: "Not authenticated")
        }
        guard account.isAdmin else {
            return jsonError(status: .forbidden, message: "Forbidden")
        }
        return try await next.respond(to: request)
    }
}
