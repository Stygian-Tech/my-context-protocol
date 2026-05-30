import Vapor

/// User-to-server OAuth for a GitHub App (e.g. when **Request user authorization (OAuth) during installation** is enabled).
/// Uses the GitHub App’s **Client ID** and **Client secret** (not `GITHUB_CLIENT_*` from the separate OAuth app used for login).
enum GitHubAppUserOAuthService {
    private struct TokenRequest: Content {
        let client_id: String
        let client_secret: String
        let code: String
        let redirect_uri: String
    }

    private struct TokenResponse: Content {
        let access_token: String?
        let error: String?
        let error_description: String?
    }

    private struct GitHubUser: Content {
        let id: Int
    }

    /// Exchanges `code` from the redirect to **User authorization callback URL** / install callback.
    /// `redirectUri` must match that URL exactly (same value as `GITHUB_APP_SETUP_CALLBACK_URL`).
    static func exchangeInstallOAuthCode(
        code: String,
        redirectUri: String,
        client: Client,
        logger: Logger
    ) async throws -> String {
        guard let clientId = Environment.get("GITHUB_APP_CLIENT_ID"), !clientId.isEmpty else {
            throw Abort(.internalServerError, reason: "GITHUB_APP_CLIENT_ID not configured")
        }
        guard let clientSecret = Environment.get("GITHUB_APP_CLIENT_SECRET"), !clientSecret.isEmpty else {
            throw Abort(.internalServerError, reason: "GITHUB_APP_CLIENT_SECRET not configured")
        }

        let tokenReq = TokenRequest(
            client_id: clientId,
            client_secret: clientSecret,
            code: code,
            redirect_uri: redirectUri
        )
        let tokenResp = try await client.post("https://github.com/login/oauth/access_token") { clientReq in
            try clientReq.content.encode(tokenReq)
            clientReq.headers.contentType = .json
            clientReq.headers.add(name: "Accept", value: "application/json")
            clientReq.headers.add(name: "User-Agent", value: "MyContextProtocol-GitHubApp-UserOAuth")
        }

        guard let body = tokenResp.body else {
            throw Abort(.badGateway, reason: "GitHub App user token: empty response body")
        }
        let tokenBody: TokenResponse
        do {
            tokenBody = try JSONDecoder().decode(TokenResponse.self, from: Data(buffer: body))
        } catch {
            logger.warning("GitHub App user token: JSON decode failed — \(error)")
            throw Abort(.badGateway, reason: "GitHub App user token: invalid JSON from GitHub")
        }
        guard let accessToken = tokenBody.access_token, !accessToken.isEmpty else {
            let err = tokenBody.error_description ?? tokenBody.error ?? "token exchange failed"
            throw Abort(.badGateway, reason: "GitHub App user token: \(err)")
        }
        return accessToken
    }

    static func fetchGitHubUserId(
        accessToken: String,
        client: Client,
        logger: Logger
    ) async throws -> Int64 {
        let userResp = try await client.get("https://api.github.com/user") { clientReq in
            clientReq.headers.bearerAuthorization = BearerAuthorization(token: accessToken)
            clientReq.headers.add(name: "Accept", value: "application/vnd.github.v3+json")
            clientReq.headers.add(name: "User-Agent", value: "MyContextProtocol-GitHubApp-UserOAuth")
        }
        guard let data = userResp.body.map({ Data(buffer: $0) }), !data.isEmpty else {
            logger.warning("GitHub App user token: /user empty body, status=\(userResp.status.code)")
            throw Abort(.badGateway, reason: "GitHub /user empty response")
        }
        guard (200 ..< 300).contains(userResp.status.code) else {
            struct GitHubError: Decodable { let message: String? }
            let msg = (try? JSONDecoder().decode(GitHubError.self, from: data))?.message
                ?? String(data: data, encoding: .utf8).map { String($0.prefix(120)) } ?? "unknown"
            logger.warning("GitHub App user token: /user status=\(userResp.status.code), \(msg)")
            throw Abort(.badGateway, reason: "GitHub /user request failed")
        }
        let ghUser: GitHubUser
        do {
            ghUser = try JSONDecoder().decode(GitHubUser.self, from: data)
        } catch {
            logger.warning("GitHub App user token: /user decode failed — \(error)")
            throw Abort(.badGateway, reason: "GitHub /user decode failed")
        }
        return Int64(ghUser.id)
    }
}
