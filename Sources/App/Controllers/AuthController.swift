import Crypto
import Fluent
import Vapor

struct AuthController {
    static func login(req: Request) async throws -> Response {
        struct LoginRequest: Content {
            let email: String
            let password: String
        }

        let login = try req.content.decode(LoginRequest.self)
        let account = try await Account.query(on: req.db)
            .filter(\.$email == login.email)
            .first()

        guard let account = account else {
            return Response(status: .unauthorized, body: .init(string: "Invalid credentials"))
        }

        let hash = try Bcrypt.verify(login.password, created: account.passwordHash)
        guard hash else {
            return Response(status: .unauthorized, body: .init(string: "Invalid credentials"))
        }

        req.session.data["accountId"] = account.id?.uuidString
        return Response(status: .ok, body: .init(string: "{\"ok\":true}"))
    }

    static func logout(req: Request) async throws -> Response {
        req.session.destroy()
        return Response(status: .ok, body: .init(string: "{\"ok\":true}"))
    }
}
