import Fluent
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
    /// PEM text for the GitHub App private key (normalized for Docker / single-line env).
    static func loadPrivatePEM() throws -> String {
        if let b64 = Environment.get("GITHUB_APP_PRIVATE_KEY_BASE64"), !b64.isEmpty {
            return try decodeBase64ToNormalizedPEM(b64)
        }
        guard let raw = Environment.get("GITHUB_APP_PRIVATE_KEY"), !raw.isEmpty else {
            throw Abort(.internalServerError, reason: "GITHUB_APP_PRIVATE_KEY not configured")
        }
        let pem = normalizeGitHubAppPrivateKeyPEM(raw)
        try validatePEMHasBookends(pem)
        return pem
    }

    /// Base64 of the PEM file bytes (recommended for Docker — multiline `GITHUB_APP_PRIVATE_KEY` often breaks).
    private static func decodeBase64ToNormalizedPEM(_ b64: String) throws -> String {
        var cleaned = b64.filter { !$0.isWhitespace }
        cleaned = cleaned.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let pad = (4 - cleaned.count % 4) % 4
        cleaned += String(repeating: "=", count: pad)
        guard let data = Data(base64Encoded: cleaned),
              let pem = String(data: data, encoding: .utf8), !pem.isEmpty else {
            throw Abort(.internalServerError, reason: "GITHUB_APP_PRIVATE_KEY_BASE64 is invalid base64")
        }
        let normalized = normalizeGitHubAppPrivateKeyPEM(pem)
        try validatePEMHasBookends(normalized)
        return normalized
    }

    private static func validatePEMHasBookends(_ pem: String) throws {
        guard pem.contains("-----BEGIN"), pem.contains("-----END") else {
            throw Abort(
                .internalServerError,
                reason: "GitHub App private key must be PEM (-----BEGIN … -----END). Use GITHUB_APP_PRIVATE_KEY_BASE64 in Docker."
            )
        }
    }

    /// Fixes env mangling: UTF-8 BOM, literal `\\n`, missing newlines after BEGIN / before END, single-line base64 body.
    private static func normalizeGitHubAppPrivateKeyPEM(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("\u{FEFF}") {
            s.removeFirst()
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if s.count >= 2, s.first == "\"", s.last == "\"" {
            s = String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        s = s.replacingOccurrences(of: "\\n", with: "\n")
        s = s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")

        let beginMarkers = [
            "-----BEGIN RSA PRIVATE KEY-----",
            "-----BEGIN PRIVATE KEY-----",
        ]
        let endMarkers = [
            "-----END RSA PRIVATE KEY-----",
            "-----END PRIVATE KEY-----",
        ]
        for begin in beginMarkers where s.contains(begin) {
            if !s.contains(begin + "\n") {
                s = s.replacingOccurrences(of: begin, with: begin + "\n")
            }
        }
        for end in endMarkers where s.contains(end) {
            if !s.contains("\n" + end) {
                s = s.replacingOccurrences(of: end, with: "\n" + end)
            }
        }
        return wrapLongBase64LinesInPEM(s)
    }

    /// PEM readers expect ~64-char base64 lines; a single long line often triggers OpenSSL `bioConversionFailure`.
    private static func wrapLongBase64LinesInPEM(_ pem: String) -> String {
        let lines = pem.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var out: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("-----") || trimmed.isEmpty {
                out.append(line)
                continue
            }
            if trimmed.count <= 64 {
                out.append(trimmed)
                continue
            }
            var i = trimmed.startIndex
            while i < trimmed.endIndex {
                let end = trimmed.index(i, offsetBy: 64, limitedBy: trimmed.endIndex) ?? trimmed.endIndex
                out.append(String(trimmed[i..<end]))
                i = end
            }
        }
        return out.joined(separator: "\n")
    }

    /// Signed JWT (`RS256`) for GitHub App authentication.
    static func createAppJWT() throws -> String {
        guard let clientId = Environment.get("GITHUB_APP_CLIENT_ID"), !clientId.isEmpty else {
            throw Abort(.internalServerError, reason: "GITHUB_APP_CLIENT_ID not configured")
        }
        let pem = try loadPrivatePEM()
        let now = Date()
        let claims = GitHubAppJWTClaims(
            iss: IssuerClaim(value: clientId),
            iat: IssuedAtClaim(value: now.addingTimeInterval(-60)),
            exp: ExpirationClaim(value: now.addingTimeInterval(600))
        )
        do {
            let signer = try JWTSigner.rs256(key: .private(pem: Array(pem.utf8)))
            return try signer.sign(claims)
        } catch {
            throw Abort(
                .internalServerError,
                reason: "GitHub App JWT signing failed (check PEM). For Docker use GITHUB_APP_PRIVATE_KEY_BASE64. Underlying: \(error)"
            )
        }
    }

    /// `GET /app/installations/{id}` — confirms which GitHub account owns the installation (JWT auth).
    static func fetchInstallation(
        installationId: Int64,
        client: Client,
        logger: Logger,
        db: Database? = nil
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
            if response.status == .notFound, let db {
                try? await GitHubAppInstallationCleanup.clearReferences(
                    installationId: installationId,
                    on: db,
                    logger: logger
                )
            }
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
        logger: Logger,
        db: Database? = nil
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
            if response.status == .notFound, let db {
                try? await GitHubAppInstallationCleanup.clearReferences(
                    installationId: installationId,
                    on: db,
                    logger: logger
                )
            }
            throw Abort(
                .badGateway,
                reason: "GitHub installation token exchange failed (status \(response.status.code)); if you removed the GitHub App from GitHub, reinstall it from the product."
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
        logger: Logger,
        db: Database? = nil
    ) async throws -> String {
        if let installationId {
            try await createInstallationToken(
                installationId: installationId,
                client: client,
                logger: logger,
                db: db
            )
        } else {
            oauthToken
        }
    }
}
