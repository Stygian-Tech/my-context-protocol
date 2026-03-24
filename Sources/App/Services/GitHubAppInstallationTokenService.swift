import Foundation
import JWTKit
import Vapor

/// JWT claims for `Authorization: Bearer` when calling GitHub App server-to-server APIs.
private struct GitHubAppJWTClaims: JWTPayload {
    var iss: IssuerClaim
    var iat: IssuedAtClaim
    var exp: ExpirationClaim

    func verify(using _: JWTSigner) throws {
        try exp.verifyNotExpired()
    }
}

/// Minimal metadata from `GET /app/installations/{id}` (used to tie GitHub install to our `Account`).
struct GitHubInstallationMeta: Sendable {
    let installationId: Int64
    let accountId: Int64
    let accountType: String
}

enum GitHubAppInstallationTokenService {
    /// PEM text for the GitHub App private key.
    static func loadPrivatePEM() throws -> String {
        if let b64 = Environment.get("GITHUB_APP_PRIVATE_KEY_BASE64"), !b64.isEmpty {
            let cleaned = b64.filter { !$0.isWhitespace }
            guard let data = Data(base64Encoded: cleaned),
                  let pem = String(data: data, encoding: .utf8), !pem.isEmpty else {
                throw Abort(.internalServerError, reason: "GITHUB_APP_PRIVATE_KEY_BASE64 is invalid")
            }
            return pem
        }
        guard let pem = Environment.get("GITHUB_APP_PRIVATE_KEY"), !pem.isEmpty else {
            throw Abort(.internalServerError, reason: "GITHUB_APP_PRIVATE_KEY not configured")
        }
        return pem
    }

    /// Signed JWT (`RS256`) for GitHub App authentication.
    static func createAppJWT() throws -> String {
        guard let clientId = Environment.get("GITHUB_APP_CLIENT_ID"), !clientId.isEmpty else {
            throw Abort(.internalServerError, reason: "GITHUB_APP_CLIENT_ID not configured")
        }
        let pem = try loadPrivatePEM()
        let signer = try JWTSigner.rs256(key: .private(pem: Array(pem.utf8)))
        let now = Date()
        let claims = GitHubAppJWTClaims(
            iss: IssuerClaim(value: clientId),
            iat: IssuedAtClaim(value: now.addingTimeInterval(-60)),
            exp: ExpirationClaim(value: now.addingTimeInterval(600))
        )
        return try signer.sign(claims)
    }

    /// `GET /app/installations/{id}` — confirms which GitHub account owns the installation (JWT auth).
    static func fetchInstallation(
        installationId: Int64,
        client: Client,
        logger: Logger
    ) async throws -> GitHubInstallationMeta {
        let jwt = try createAppJWT()
        let url = "https://api.github.com/app/installations/\(installationId)"
        struct Body: Decodable {
            let id: Int64
            let account: Account
            struct Account: Decodable {
                let id: Int64
                let type: String
            }
        }
        let response = try await client.get(URI(string: url)) { req in
            req.headers.bearerAuthorization = BearerAuthorization(token: jwt)
            req.headers.add(name: "Accept", value: "application/vnd.github+json")
            req.headers.add(name: "X-GitHub-Api-Version", value: "2022-11-28")
            req.headers.add(name: "User-Agent", value: "MyContextProtocol-GitHub-App")
        }.get()
        guard response.status == .ok else {
            let body = response.body.map { String(buffer: $0) } ?? ""
            logger.warning("GitHub GET installation failed status=\(response.status.code) body=\(body.prefix(500))")
            throw Abort(
                .badGateway,
                reason: "GitHub installation lookup failed (status \(response.status.code))"
            )
        }
        let decoded = try response.content.decode(Body.self)
        return GitHubInstallationMeta(
            installationId: decoded.id,
            accountId: decoded.account.id,
            accountType: decoded.account.type
        )
    }

    /// `POST /app/installations/{id}/access_tokens` — returns a bearer token for repository API calls.
    static func createInstallationToken(
        installationId: Int64,
        client: Client,
        logger: Logger
    ) async throws -> String {
        let jwt = try createAppJWT()
        let url = "https://api.github.com/app/installations/\(installationId)/access_tokens"

        struct EmptyPayload: Content {}

        struct TokenBody: Content {
            let token: String?
        }

        let response = try await client.post(URI(string: url)) { req in
            try req.content.encode(EmptyPayload())
            req.headers.bearerAuthorization = BearerAuthorization(token: jwt)
            req.headers.add(name: "Accept", value: "application/vnd.github+json")
            req.headers.add(name: "X-GitHub-Api-Version", value: "2022-11-28")
            req.headers.add(name: "User-Agent", value: "MyContextProtocol-GitHub-App")
        }.get()

        guard response.status == .created else {
            let body = response.body.map { String(buffer: $0) } ?? ""
            logger.warning("GitHub installation token failed status=\(response.status.code) body=\(body.prefix(500))")
            throw Abort(
                .badGateway,
                reason: "GitHub installation token exchange failed (status \(response.status.code))"
            )
        }

        let decoded = try response.content.decode(TokenBody.self)
        guard let token = decoded.token, !token.isEmpty else {
            throw Abort(.badGateway, reason: "GitHub installation token missing in response")
        }
        return token
    }

    /// Prefer installation access token when `installationId` is set; otherwise use the user OAuth token.
    static func bearerTokenForGitHubREST(
        installationId: Int64?,
        oauthToken: String,
        client: Client,
        logger: Logger
    ) async throws -> String {
        if let installationId {
            try await createInstallationToken(installationId: installationId, client: client, logger: logger)
        } else {
            oauthToken
        }
    }
}
