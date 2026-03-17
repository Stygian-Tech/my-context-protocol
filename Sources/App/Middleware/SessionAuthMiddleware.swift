import Fluent
import Vapor

struct SessionAuthMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard let accountIdString = request.session.data["accountId"],
              let accountId = UUID(uuidString: accountIdString) else {
            return jsonError(status: .unauthorized, message: "Not authenticated")
        }

        let account = try await Account.find(accountId, on: request.db)
        guard account != nil else {
            request.session.destroy()
            return jsonError(status: .unauthorized, message: "Invalid session")
        }

        request.storage[AccountKey.self] = account
        return try await next.respond(to: request)
    }
}

struct ErrorResponse: Content {
    let error: String
}

func jsonError(status: HTTPStatus, message: String) -> Response {
    let body = ErrorResponse(error: message)
    var headers = HTTPHeaders()
    headers.contentType = .json
    let jsonString: String
    do {
        let data = try JSONEncoder().encode(body)
        jsonString = String(data: data, encoding: .utf8) ?? "{\"error\":\"Internal error\"}"
    } catch {
        jsonString = "{\"error\":\"Internal error\"}"
    }
    return Response(status: status, headers: headers, body: .init(string: jsonString))
}

struct AccountKey: StorageKey {
    typealias Value = Account?
}
