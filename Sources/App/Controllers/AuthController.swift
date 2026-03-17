import Fluent
import Vapor

struct AuthController {
    static func githubInitiate(req: Request) async throws -> Response {
        guard let clientId = Environment.get("GITHUB_CLIENT_ID"), !clientId.isEmpty else {
            throw Abort(.internalServerError, reason: "GITHUB_CLIENT_ID not configured")
        }
        let redirectUri = Environment.get("GITHUB_OAUTH_REDIRECT_URI") ?? "http://localhost:8080/auth/github/callback"
        let returnTo = req.query[String.self, at: "return_to"] ?? "http://localhost:3000/"

        let state = UUID().uuidString
        req.session.data["oauth_state"] = state
        req.session.data["oauth_return_to"] = returnTo

        var components = URLComponents(string: "https://github.com/login/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: "read:user user:email repo"),
        ]
        guard let url = components.url else {
            throw Abort(.internalServerError, reason: "Invalid OAuth URL")
        }
        return req.redirect(to: url.absoluteString, redirectType: .normal)
    }

    static func githubCallback(req: Request) async throws -> Response {
        guard let clientId = Environment.get("GITHUB_CLIENT_ID"), !clientId.isEmpty,
              let clientSecret = Environment.get("GITHUB_CLIENT_SECRET"), !clientSecret.isEmpty else {
            throw Abort(.internalServerError, reason: "GitHub OAuth not configured")
        }
        let redirectUri = Environment.get("GITHUB_OAUTH_REDIRECT_URI") ?? "http://localhost:8080/auth/github/callback"

        let code = req.query[String.self, at: "code"]
        let state = req.query[String.self, at: "state"]
        let storedState = req.session.data["oauth_state"]
        let returnTo = req.session.data["oauth_return_to"] ?? "http://localhost:3000/"

        req.session.data["oauth_state"] = nil
        req.session.data["oauth_return_to"] = nil

        guard let code = code, !code.isEmpty else {
            return req.redirect(to: returnTo + (returnTo.contains("?") ? "&" : "?") + "error=missing_code", redirectType: .normal)
        }
        guard let state = state, let storedState = storedState, state == storedState, !state.isEmpty else {
            return req.redirect(to: returnTo + (returnTo.contains("?") ? "&" : "?") + "error=invalid_state", redirectType: .normal)
        }

        struct TokenRequest: Content {
            let client_id: String
            let client_secret: String
            let code: String
            let redirect_uri: String
        }
        struct TokenResponse: Content {
            let access_token: String?
            let error: String?
            let error_description: String?
        }

        let tokenReq = TokenRequest(
            client_id: clientId,
            client_secret: clientSecret,
            code: code,
            redirect_uri: redirectUri
        )
        let tokenResp = try await req.client.post("https://github.com/login/oauth/access_token") { clientReq in
            try clientReq.content.encode(tokenReq)
            clientReq.headers.contentType = .json
            clientReq.headers.add(name: "Accept", value: "application/json")
        }
        let tokenBody = try tokenResp.content.decode(TokenResponse.self)
        guard let accessToken = tokenBody.access_token, !accessToken.isEmpty else {
            let err = tokenBody.error_description ?? tokenBody.error ?? "Token exchange failed"
            return req.redirect(to: returnTo + (returnTo.contains("?") ? "&" : "?") + "error=\(err.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? err)", redirectType: .normal)
        }

        struct GitHubUser: Content {
            let id: Int
            let login: String?
            let avatar_url: String?
            let email: String?
        }

        let userResp = try await req.client.get("https://api.github.com/user") { clientReq in
            clientReq.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
            clientReq.headers.add(name: "Accept", value: "application/vnd.github.v3+json")
        }
        let ghUser = try userResp.content.decode(GitHubUser.self)

        let account: Account
        if let existing = try await Account.query(on: req.db).filter(\.$githubId == Int64(ghUser.id)).first() {
            existing.login = ghUser.login ?? existing.login
            existing.avatarUrl = ghUser.avatar_url
            existing.email = ghUser.email ?? existing.email
            if let encrypted = try? TokenEncryption.encrypt(accessToken) {
                existing.githubTokenEncrypted = encrypted
            }
            try await existing.save(on: req.db)
            account = existing
        } else {
            let newAccount = Account(
                githubId: Int64(ghUser.id),
                login: ghUser.login ?? "user\(ghUser.id)",
                avatarUrl: ghUser.avatar_url,
                email: ghUser.email
            )
            if let encrypted = try? TokenEncryption.encrypt(accessToken) {
                newAccount.githubTokenEncrypted = encrypted
            }
            try await newAccount.save(on: req.db)
            account = newAccount
        }

        req.session.data["accountId"] = account.id?.uuidString
        return req.redirect(to: returnTo, redirectType: .normal)
    }

    static func me(req: Request) async throws -> UserResponse {
        guard let accountIdString = req.session.data["accountId"],
              let accountId = UUID(uuidString: accountIdString) else {
            throw Abort(.unauthorized, reason: "Not authenticated")
        }
        guard let account = try await Account.find(accountId, on: req.db) else {
            req.session.destroy()
            throw Abort(.unauthorized, reason: "Invalid session")
        }
        return UserResponse(
            id: account.id!.uuidString,
            email: account.email,
            login: account.login,
            avatar_url: account.avatarUrl
        )
    }

    static func logout(req: Request) async throws -> Response {
        req.session.destroy()
        return Response(status: .noContent)
    }
}

struct UserResponse: Content {
    let id: String
    let email: String?
    let login: String?
    let avatar_url: String?

    enum CodingKeys: String, CodingKey {
        case id, email, login
        case avatar_url = "avatar_url"
    }
}
