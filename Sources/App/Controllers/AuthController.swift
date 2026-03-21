import Fluent
import Vapor

private func userResponse(for account: Account, suggestedGithubAppInstall: Bool = false) -> UserResponse {
    UserResponse(
        id: account.id!.uuidString,
        email: account.email,
        login: account.login,
        avatar_url: account.avatarUrl,
        plan: account.hasProEntitlements ? "pro" : "free",
        internal_pro_bypass: InternalProBypass.matches(login: account.login, githubId: account.githubId),
        can_manage_subscription: account.hasStripeCustomerRecord,
        suggested_github_app_install: suggestedGithubAppInstall,
        app_env: AppEnvironment.appEnvString,
        non_production_bypasses: AppEnvironment.nonProductionBypassesActive
    )
}

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
            clientReq.headers.add(name: "User-Agent", value: "MyContextProtocol-OAuth")
        }

        // Read raw body and decode manually to avoid 415 when GitHub returns HTML error pages
        guard let body = tokenResp.body else {
            return req.redirect(to: returnTo + (returnTo.contains("?") ? "&" : "?") + "error=token_exchange_failed", redirectType: .normal)
        }
        let tokenBody: TokenResponse
        do {
            tokenBody = try JSONDecoder().decode(TokenResponse.self, from: Data(buffer: body))
        } catch {
            return req.redirect(to: returnTo + (returnTo.contains("?") ? "&" : "?") + "error=token_decode_failed", redirectType: .normal)
        }
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
            clientReq.headers.add(name: "User-Agent", value: "MyContextProtocol-OAuth")
        }

        let userBodyData: Data? = userResp.body.map { Data(buffer: $0) }
        guard let data = userBodyData, !data.isEmpty else {
            req.logger.warning("GitHub user API: empty body, status=\(userResp.status.code)")
            return req.redirect(to: returnTo + (returnTo.contains("?") ? "&" : "?") + "error=user_fetch_failed", redirectType: .normal)
        }

        guard (200 ..< 300).contains(userResp.status.code) else {
            struct GitHubError: Decodable { let message: String? }
            let msg = (try? JSONDecoder().decode(GitHubError.self, from: data))?.message ?? String(data: data, encoding: .utf8).map { String($0.prefix(100)) } ?? "unknown"
            req.logger.warning("GitHub user API: status=\(userResp.status.code), body=\(msg)")
            return req.redirect(to: returnTo + (returnTo.contains("?") ? "&" : "?") + "error=user_fetch_failed", redirectType: .normal)
        }

        let ghUser: GitHubUser
        do {
            ghUser = try JSONDecoder().decode(GitHubUser.self, from: data)
        } catch {
            req.logger.warning("GitHub user API: decode failed - \(error), body=\(String(data: data, encoding: .utf8).map { String($0.prefix(200)) } ?? "?")")
            return req.redirect(to: returnTo + (returnTo.contains("?") ? "&" : "?") + "error=user_fetch_failed", redirectType: .normal)
        }

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
        // Token-based handoff: 302 redirect with one-time token. Using 302 (not HTML meta refresh)
        // ensures a single navigation so the frontend middleware sees auth_token exactly once.
        let handoffToken = UUID().uuidString
        AuthTokenStore.put(handoffToken, accountId: account.id!.uuidString)
        let successUrl = returnTo + (returnTo.contains("?") ? "&" : "?") + "auth_token=" + handoffToken
        return req.redirect(to: successUrl, redirectType: .normal)
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
        let suggest = try await Self.suggestedGithubAppMe(account: account, db: req.db)
        return userResponse(for: account, suggestedGithubAppInstall: suggest)
    }

    /// Repositories the session user can access on GitHub (uses stored OAuth token).
    static func listGithubRepos(req: Request) async throws -> [GithubRepoListItem] {
        guard let account = req.storage[AccountKey.self], let account = account else {
            throw Abort(.unauthorized, reason: "Not authenticated")
        }
        guard let encrypted = account.githubTokenEncrypted,
              let token = try? TokenEncryption.decrypt(encrypted), !token.isEmpty else {
            throw Abort(.badRequest, reason: "No GitHub token. Re-authorize with repo scope.")
        }
        return try await GitHubRepositoriesService.listUserRepositories(
            token: token,
            client: req.client,
            logger: req.logger
        )
    }

    /// Exchange one-time auth token for session.
    /// - If `redirect` query param is present: sets session, redirects to that URL (avoids CORS).
    /// - Else: returns JSON (for fetch with credentials: include).
    static func confirm(req: Request) async throws -> Response {
        guard let token = req.query[String.self, at: "token"], !token.isEmpty else {
            throw Abort(.badRequest, reason: "Missing token")
        }
        guard let accountId = AuthTokenStore.consume(token) else {
            throw Abort(.unauthorized, reason: "Invalid or expired token")
        }
        guard let account = try await Account.find(UUID(uuidString: accountId), on: req.db) else {
            throw Abort(.unauthorized, reason: "Account not found")
        }
        req.session.data["accountId"] = accountId

        if let redirectTo = req.query[String.self, at: "redirect"], !redirectTo.isEmpty,
           let url = URL(string: redirectTo), url.scheme == "http" || url.scheme == "https" {
            return req.redirect(to: redirectTo, redirectType: .normal)
        }

        let suggest = try await Self.suggestedGithubAppMe(account: account, db: req.db)
        return try await userResponse(for: account, suggestedGithubAppInstall: suggest).encodeResponse(for: req)
    }

    /// Pro users with GitHub repos missing App installation, when slug + webhook base URL are configured.
    private static func suggestedGithubAppMe(account: Account, db: Database) async throws -> Bool {
        guard account.hasProEntitlements else { return false }
        guard let slug = Environment.get("GITHUB_APP_SLUG"), !slug.isEmpty else { return false }
        guard let base = Environment.get("WEBHOOK_BASE_URL"), !base.isEmpty else { return false }
        guard let aid = account.id else { return false }
        let projects = try await Project.query(on: db).filter(\.$account.$id == aid).all()
        for project in projects {
            let conns = try await project.$repoConnections.get(on: db)
            if conns.contains(where: { $0.provider == "github" && $0.githubInstallationId == nil }) {
                return true
            }
        }
        return false
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
    let plan: String
    /// True when this account matches `INTERNAL_PRO_GITHUB_*` env allowlists.
    let internal_pro_bypass: Bool
    /// True when a Stripe Customer exists (Customer Portal / paid subscription management).
    let can_manage_subscription: Bool
    /// Hint for Pro: install the GitHub App so webhooks can use installation tokens.
    let suggested_github_app_install: Bool
    /// Backend `APP_ENV`: `local`, `dev`, or `prod`.
    let app_env: String
    /// True when non-production Pro/rate-limit bypasses are active (`APP_ENV` local/dev and `STRICT_PRO_GATING` unset).
    let non_production_bypasses: Bool

    enum CodingKeys: String, CodingKey {
        case id, email, login, plan
        case avatar_url = "avatar_url"
        case internal_pro_bypass = "internal_pro_bypass"
        case can_manage_subscription = "can_manage_subscription"
        case suggested_github_app_install = "suggested_github_app_install"
        case app_env = "app_env"
        case non_production_bypasses = "non_production_bypasses"
    }
}
