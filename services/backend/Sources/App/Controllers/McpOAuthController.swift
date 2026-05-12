import Fluent
import Foundation
import Vapor

// MARK: - Metadata DTOs

struct OAuthProtectedResourceMetadata: Content {
    var resource: String
    var authorization_servers: [String]
    var scopes_supported: [String]
    var bearer_methods_supported: [String]
}

struct OAuthAuthorizationServerMetadata: Content {
    var issuer: String
    var authorization_endpoint: String
    var token_endpoint: String
    var registration_endpoint: String
    var response_types_supported: [String]
    var grant_types_supported: [String]
    var code_challenge_methods_supported: [String]
    var token_endpoint_auth_methods_supported: [String]
    var scopes_supported: [String]
}

struct OAuthTokenSuccess: Content {
    var access_token: String
    var token_type: String
    var expires_in: Int
    var scope: String
}

struct OAuthTokenError: Content {
    var error: String
    var error_description: String?
}

private struct TokenRequestForm: Content {
    var grant_type: String?
    var code: String?
    var redirect_uri: String?
    var client_id: String?
    var client_secret: String?
    var code_verifier: String?
}

// MARK: - Controller

enum McpOAuthController {
    // MARK: Discovery

    static func protectedResourceMetadata(req: Request) async throws -> OAuthProtectedResourceMetadata {
        try requireOAuthEnabled()
        guard let issuer = RequestPublicOrigin.origin(for: req) else {
            throw Abort(.badRequest, reason: "Cannot determine issuer URL")
        }
        return OAuthProtectedResourceMetadata(
            resource: issuer,
            authorization_servers: [issuer],
            scopes_supported: [McpOAuthConstants.defaultScope],
            bearer_methods_supported: ["header"]
        )
    }

    static func authorizationServerMetadata(req: Request) async throws -> OAuthAuthorizationServerMetadata {
        try requireOAuthEnabled()
        guard let origin = RequestPublicOrigin.origin(for: req) else {
            throw Abort(.badRequest, reason: "Cannot determine issuer URL")
        }
        return OAuthAuthorizationServerMetadata(
            issuer: origin,
            authorization_endpoint: "\(origin)/authorize",
            token_endpoint: "\(origin)/token",
            registration_endpoint: "\(origin)/register",
            response_types_supported: ["code"],
            grant_types_supported: ["authorization_code", "client_credentials"],
            code_challenge_methods_supported: ["S256"],
            token_endpoint_auth_methods_supported: ["client_secret_post", "none"],
            scopes_supported: [McpOAuthConstants.defaultScope]
        )
    }

    // MARK: Dynamic Client Registration (RFC 7591)

    private struct RegistrationRequest: Content {
        var redirect_uris: [String]
        var client_name: String?
        var grant_types: [String]?
        var token_endpoint_auth_method: String?
        var response_types: [String]?
    }

    static func registerClient(req: Request) async throws -> Response {
        try requireOAuthEnabled()
        let project = try requireResolvedProject(req)
        let body = try req.content.decode(RegistrationRequest.self)

        guard !body.redirect_uris.isEmpty else {
            throw Abort(.badRequest, reason: "redirect_uris must be non-empty")
        }
        for uriString in body.redirect_uris {
            guard URL(string: uriString) != nil else {
                throw Abort(.badRequest, reason: "Invalid redirect_uri: \(uriString)")
            }
        }

        let authMethod = body.token_endpoint_auth_method ?? "none"
        let isConfidential = (authMethod == "client_secret_post")
        guard authMethod == "none" || authMethod == "client_secret_post" else {
            throw Abort(.badRequest, reason: "Unsupported token_endpoint_auth_method: \(authMethod)")
        }

        let requestedGrants = body.grant_types ?? ["authorization_code"]
        let allowedGrantSet = Set(["authorization_code", "client_credentials"])
        for g in requestedGrants where !allowedGrantSet.contains(g) {
            throw Abort(.badRequest, reason: "Unsupported grant_type: \(g)")
        }

        let clientId = UUID().uuidString
        var rawSecret: String? = nil
        var secretHash: String? = nil
        if isConfidential {
            let s = McpOAuthCrypto.randomToken(prefix: "mcs_")
            rawSecret = s
            secretHash = McpOAuthCrypto.sha256Hex(s)
        }

        let urisJson = String(data: try JSONEncoder().encode(body.redirect_uris), encoding: .utf8)!
        let client = McpOAuthClient(
            publicClientId: clientId,
            clientSecretHash: secretHash,
            isConfidential: isConfidential,
            redirectUrisJson: urisJson,
            allowedGrants: requestedGrants.joined(separator: ","),
            status: "active",
            projectId: project.id!
        )
        try await client.save(on: req.db)

        var responseDict: [String: Any] = [
            "client_id": clientId,
            "redirect_uris": body.redirect_uris,
            "grant_types": requestedGrants,
            "response_types": body.response_types ?? ["code"],
            "token_endpoint_auth_method": authMethod,
        ]
        if let secret = rawSecret { responseDict["client_secret"] = secret }

        let json = try JSONSerialization.data(withJSONObject: responseDict)
        var headers = HTTPHeaders()
        headers.contentType = .json
        return Response(status: .created, headers: headers, body: .init(data: json))
    }

    // MARK: Authorization (user code + PKCE)

    static func authorize(req: Request) async throws -> Response {
        try requireOAuthEnabled()
        let project = try requireResolvedProject(req)

        guard let clientId = req.query[String.self, at: "client_id"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !clientId.isEmpty else {
            throw Abort(.badRequest, reason: "Missing client_id")
        }
        guard let redirectUri = req.query[String.self, at: "redirect_uri"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !redirectUri.isEmpty else {
            throw Abort(.badRequest, reason: "Missing redirect_uri")
        }
        guard let responseType = req.query[String.self, at: "response_type"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !responseType.isEmpty else {
            throw Abort(.badRequest, reason: "Missing response_type")
        }
        let state = req.query[String.self, at: "state"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let codeChallenge = req.query[String.self, at: "code_challenge"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !codeChallenge.isEmpty else {
            return try redirectOAuthError(
                req: req,
                redirectUri: redirectUri,
                state: state,
                error: "invalid_request",
                description: "code_challenge is required"
            )
        }
        guard let codeChallengeMethod = req.query[String.self, at: "code_challenge_method"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !codeChallengeMethod.isEmpty else {
            throw Abort(.badRequest, reason: "Missing code_challenge_method")
        }
        let scope = req.query[String.self, at: "scope"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? McpOAuthConstants.defaultScope

        guard responseType == "code" else {
            return try redirectOAuthError(
                req: req,
                redirectUri: redirectUri,
                state: state,
                error: "unsupported_response_type",
                description: "Only code is supported"
            )
        }
        guard !state.isEmpty else {
            throw Abort(.badRequest, reason: "state is required")
        }
        guard codeChallengeMethod.uppercased() == "S256" else {
            return try redirectOAuthError(
                req: req,
                redirectUri: redirectUri,
                state: state,
                error: "invalid_request",
                description: "code_challenge_method must be S256"
            )
        }

        guard let clientRow = try await McpOAuthClient.query(on: req.db)
            .filter(\.$publicClientId == clientId)
            .first(),
            clientRow.isActive else {
            throw Abort(.badRequest, reason: "Unknown client_id")
        }
        if let clientProjectId = clientRow.$project.id, clientProjectId != project.id! {
            throw Abort(.badRequest, reason: "Unknown client_id")
        }
        guard clientRow.allowsGrant("authorization_code") else {
            return try redirectOAuthError(
                req: req,
                redirectUri: redirectUri,
                state: state,
                error: "unauthorized_client",
                description: "Client cannot use authorization_code"
            )
        }
        let uris = try clientRow.parsedRedirectUris()
        guard uris.contains(redirectUri) else {
            throw Abort(.badRequest, reason: "redirect_uri is not registered for this client")
        }

        let normalizedScope = try normalizeScope(scope)
        guard clientRow.isConfidential == false else {
            throw Abort(.badRequest, reason: "Confidential clients are not supported for browser authorization_code in this version")
        }

        let now = Date()
        let expires = now.addingTimeInterval(McpOAuthConstants.pendingAuthorizationTTLSeconds)
        let pending = McpOAuthPendingAuthorization(
            projectId: project.id!,
            clientId: clientRow.id!,
            redirectUri: redirectUri,
            state: state,
            scope: normalizedScope,
            codeChallenge: codeChallenge,
            codeChallengeMethod: "S256",
            expiresAt: expires
        )
        try await pending.save(on: req.db)

        if let accountIdString = req.session.data["accountId"],
           let accountId = UUID(uuidString: accountIdString),
           try await accountOwnsProject(accountId: accountId, projectId: project.id!, db: req.db) {
            return req.redirect(
                to: consentRedirectPath(pendingId: pending.id!),
                redirectType: .normal
            )
        }

        let link = McpOAuthResumeURL.githubMcpOauthStartLink(pending: pending.id!)
        return req.redirect(to: link, redirectType: .normal)
    }

    // MARK: GitHub resume (API host)

    static func githubMcpOauthStart(req: Request) async throws -> Response {
        try requireOAuthEnabled()
        guard let ps = req.query[String.self, at: "pending"], let pid = UUID(uuidString: ps) else {
            throw Abort(.badRequest, reason: "Missing pending")
        }
        guard let pending = try await McpOAuthPendingAuthorization.query(on: req.db)
            .filter(\.$id == pid)
            .first(),
            pending.expiresAt > Date() else {
            throw Abort(.badRequest, reason: "Invalid or expired pending authorization")
        }

        let returnTo = try McpOAuthResumeURL.githubReturnTo(pending: pid)
        _ = try AppFrontendURL.validateOAuthReturnTo(returnTo, for: req)

        guard let ghClientId = Environment.get("GITHUB_CLIENT_ID"), !ghClientId.isEmpty else {
            throw Abort(.internalServerError, reason: "GITHUB_CLIENT_ID not configured")
        }
        guard let redirectUri = Environment.get("GITHUB_OAUTH_REDIRECT_URI"), !redirectUri.isEmpty else {
            throw Abort(.internalServerError, reason: "GITHUB_OAUTH_REDIRECT_URI not configured")
        }

        let state: String
        do {
            state = try SignedOAuthState.signGitHubOAuth(returnTo: returnTo)
        } catch SignedOAuthState.StateError.keyNotConfigured {
            throw Abort(.internalServerError, reason: "ENCRYPTION_KEY must be configured (32-byte base64) for OAuth state signing")
        } catch {
            throw Abort(.internalServerError, reason: "Failed to build OAuth state")
        }

        var components = URLComponents(string: "https://github.com/login/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: ghClientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: "read:user user:email"),
        ]
        guard let url = components.url else {
            throw Abort(.internalServerError, reason: "Invalid GitHub OAuth URL")
        }
        return req.redirect(to: url.absoluteString, redirectType: .normal)
    }

    static func mcpOauthResume(req: Request) async throws -> Response {
        try requireOAuthEnabled()
        guard let ps = req.query[String.self, at: "pending"], let pid = UUID(uuidString: ps) else {
            throw Abort(.badRequest, reason: "Missing pending")
        }

        if let token = req.query[String.self, at: "auth_token"], !token.isEmpty {
            guard let accountUUID = try await OAuthHandoffService.consume(token, on: req.db) else {
                throw Abort(.unauthorized, reason: "Invalid or expired auth_token")
            }
            guard let account = try await Account.find(accountUUID, on: req.db) else {
                throw Abort(.unauthorized, reason: "Account not found")
            }
            req.session.data["accountId"] = account.id!.uuidString
            let path = "/auth/mcp-oauth-resume?pending=\(pid.uuidString)"
            guard let base = AppFrontendURL.normalizedBase() else {
                throw Abort(.internalServerError, reason: "FRONTEND_URL or CORS_ORIGIN must be set")
            }
            return req.redirect(to: base + path, redirectType: .normal)
        }

        guard let accountIdString = req.session.data["accountId"],
              let accountId = UUID(uuidString: accountIdString) else {
            throw Abort(.unauthorized, reason: "Not authenticated")
        }

        guard let pending = try await McpOAuthPendingAuthorization.query(on: req.db)
            .filter(\.$id == pid)
            .first(),
            pending.expiresAt > Date() else {
            throw Abort(.badRequest, reason: "Invalid or expired pending authorization")
        }

        guard try await accountOwnsProject(accountId: accountId, projectId: pending.$project.id, db: req.db) else {
            throw Abort(.forbidden, reason: "You do not have access to this project")
        }

        guard let tenantBase = try await tenantOrigin(forProjectId: pending.$project.id, db: req.db) else {
            throw Abort(.internalServerError, reason: "Could not build tenant MCP URL")
        }
        let handoffToken = try await OAuthHandoffService.issue(accountId: accountId, on: req.db)
        let loc = "\(tenantBase)/oauth/consent?pending=\(pid.uuidString)&auth_token=\(handoffToken)"
        return req.redirect(to: loc, redirectType: .normal)
    }

    // MARK: Consent (tenant host)

    static func consentPage(req: Request) async throws -> Response {
        try requireOAuthEnabled()
        let project = try requireResolvedProject(req)
        guard let pqs = req.query[String.self, at: "pending"], let pid = UUID(uuidString: pqs) else {
            throw Abort(.badRequest, reason: "Missing pending")
        }
        guard let pending = try await McpOAuthPendingAuthorization.query(on: req.db)
            .filter(\.$id == pid)
            .with(\.$client)
            .first(),
            pending.expiresAt > Date(),
            pending.$project.id == project.id! else {
            throw Abort(.badRequest, reason: "Invalid pending authorization")
        }

        // Resolve the authenticated account. Two paths:
        //
        // 1. auth_token query param — consumed here and rendered into the form in one
        //    response, with no redirect. This avoids a session-cookie round-trip, which
        //    is critical for custom-domain MCP hosts: the platform SESSION_COOKIE_DOMAIN
        //    (e.g. .mycontextprotocol.dev) is silently rejected by browsers for unrelated
        //    domains like mcp.example.com, so any approach that relies on setting a cookie
        //    and then reading it on the next request creates an infinite redirect loop.
        //
        // 2. Session cookie — used when the platform session IS available (subdomain
        //    tenants that share the registrable domain with the platform).
        let accountId: UUID
        if let authToken = req.query[String.self, at: "auth_token"], !authToken.isEmpty {
            guard let uuid = try await OAuthHandoffService.consume(authToken, on: req.db) else {
                throw Abort(.unauthorized, reason: "Invalid or expired auth_token")
            }
            accountId = uuid
        } else if let str = req.session.data["accountId"], let uuid = UUID(uuidString: str) {
            accountId = uuid
        } else {
            let start = McpOAuthResumeURL.githubMcpOauthStartLink(pending: pid)
            return req.redirect(to: start, redirectType: .normal)
        }

        guard try await accountOwnsProject(accountId: accountId, projectId: project.id!, db: req.db) else {
            throw Abort(.forbidden, reason: "You do not have access to this project")
        }

        // Issue a single-use DB-backed consent token. Embedded as a hidden form field, it
        // simultaneously authenticates the submitter and prevents CSRF/replay without
        // relying on the session cookie — so it works for both custom domains (where the
        // platform cookie domain is rejected by the browser) and platform subdomains.
        let consentToken = try await OAuthHandoffService.issue(accountId: accountId, on: req.db)

        let client = pending.client
        let title = "Authorize \(htmlEscape(client.publicClientId))"
        let body = """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><title>\(title)</title></head>
        <body>
        <h1>\(title)</h1>
        <p>Project: <strong>\(htmlEscape(project.name))</strong></p>
        <p>Permissions: <code>\(htmlEscape(pending.scope))</code></p>
        <form method="post" action="/oauth/consent">
          <input type="hidden" name="pending" value="\(pending.id!.uuidString)"/>
          <input type="hidden" name="consent_token" value="\(consentToken)"/>
          <button type="submit" name="decision" value="approve">Approve</button>
          <button type="submit" name="decision" value="deny">Deny</button>
        </form>
        </body></html>
        """
        var headers = HTTPHeaders()
        headers.contentType = .html
        return Response(status: .ok, headers: headers, body: .init(string: body))
    }

    struct ConsentForm: Content {
        var pending: UUID
        var decision: String
        var consent_token: String
    }

    static func consentSubmit(req: Request) async throws -> Response {
        try requireOAuthEnabled()
        let project = try requireResolvedProject(req)
        let form = try req.content.decode(ConsentForm.self)

        // Validate and consume the single-use consent token. This simultaneously:
        //  • Authenticates the submitter (returns the accountId that received the form)
        //  • Prevents CSRF and replay (one-time-use, cryptographically random, DB-backed)
        //
        // Using a DB-backed token rather than the session cookie makes this work for custom
        // MCP domains, where the browser rejects the platform SESSION_COOKIE_DOMAIN
        // (.mycontextprotocol.dev) for an unrelated host like mcp.example.com.
        guard let accountId = try await OAuthHandoffService.consume(form.consent_token, on: req.db) else {
            throw Abort(.forbidden, reason: "Invalid or expired consent token")
        }

        guard let pending = try await McpOAuthPendingAuthorization.query(on: req.db)
            .filter(\.$id == form.pending)
            .with(\.$client)
            .first(),
            pending.expiresAt > Date(),
            pending.$project.id == project.id! else {
            throw Abort(.badRequest, reason: "Invalid pending authorization")
        }

        guard try await accountOwnsProject(accountId: accountId, projectId: project.id!, db: req.db) else {
            throw Abort(.forbidden, reason: "You do not have access to this project")
        }

        if form.decision != "approve" {
            try await pending.delete(on: req.db)
            return try redirectOAuthError(
                req: req,
                redirectUri: pending.redirectUri,
                state: pending.state,
                error: "access_denied",
                description: "User denied authorization"
            )
        }

        let rawCode = McpOAuthCrypto.randomToken(prefix: McpOAuthConstants.authorizationCodePrefix)
        let codeHash = McpOAuthCrypto.sha256Hex(rawCode)
        let codeRow = McpOAuthAuthorizationCode(
            codeHash: codeHash,
            projectId: pending.$project.id,
            clientId: pending.$client.id,
            accountId: accountId,
            redirectUri: pending.redirectUri,
            scope: pending.scope,
            codeChallenge: pending.codeChallenge,
            codeChallengeMethod: pending.codeChallengeMethod,
            expiresAt: Date().addingTimeInterval(McpOAuthConstants.authorizationCodeTTLSeconds)
        )
        try await codeRow.save(on: req.db)
        try await pending.delete(on: req.db)

        var c = URLComponents(string: pending.redirectUri)!
        var q = c.queryItems ?? []
        q.append(URLQueryItem(name: "code", value: rawCode))
        q.append(URLQueryItem(name: "state", value: pending.state))
        c.queryItems = q
        guard let url = c.url else {
            throw Abort(.internalServerError, reason: "Invalid redirect")
        }
        return req.redirect(to: url.absoluteString, redirectType: .normal)
    }

    // MARK: Token

    static func token(req: Request) async throws -> Response {
        try requireOAuthEnabled()
        _ = try requireResolvedProject(req)

        let form = try req.content.decode(TokenRequestForm.self)
        let grant = form.grant_type?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        switch grant {
        case "authorization_code":
            return try await tokenAuthorizationCode(req: req, form: form)
        case "client_credentials":
            return try await tokenClientCredentials(req: req, form: form)
        default:
            return try await oauthTokenErrorResponse(
                req: req,
                status: .badRequest,
                error: "unsupported_grant_type",
                description: "Unsupported grant_type"
            )
        }
    }

    private static func tokenAuthorizationCode(req: Request, form: TokenRequestForm) async throws -> Response {
        guard let code = form.code?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty,
              let redirectUri = form.redirect_uri?.trimmingCharacters(in: .whitespacesAndNewlines), !redirectUri.isEmpty,
              let clientId = form.client_id?.trimmingCharacters(in: .whitespacesAndNewlines), !clientId.isEmpty else {
            return try await oauthTokenErrorResponse(
                req: req,
                status: .badRequest,
                error: "invalid_request",
                description: "Missing code, redirect_uri, or client_id"
            )
        }
        guard let verifier = form.code_verifier?.trimmingCharacters(in: .whitespacesAndNewlines), !verifier.isEmpty else {
            return try await oauthTokenErrorResponse(
                req: req,
                status: .badRequest,
                error: "invalid_request",
                description: "code_verifier is required"
            )
        }

        guard let clientRow = try await McpOAuthClient.query(on: req.db)
            .filter(\.$publicClientId == clientId)
            .first(),
            clientRow.isActive else {
            return try await oauthTokenErrorResponse(req: req, status: .badRequest, error: "invalid_client", description: "Unknown client")
        }

        if clientRow.isConfidential {
            guard let secret = form.client_secret?.trimmingCharacters(in: .whitespacesAndNewlines), !secret.isEmpty,
                  let expected = clientRow.clientSecretHash,
                  expected == McpOAuthCrypto.sha256Hex(secret) else {
                return try await oauthTokenErrorResponse(
                    req: req,
                    status: .unauthorized,
                    error: "invalid_client",
                    description: "Invalid client credentials"
                )
            }
        }

        let codeHash = McpOAuthCrypto.sha256Hex(code)
        guard let row = try await McpOAuthAuthorizationCode.query(on: req.db)
            .filter(\.$codeHash == codeHash)
            .filter(\.$client.$id == clientRow.id!)
            .first(),
            row.expiresAt > Date(),
            row.consumedAt == nil,
            row.redirectUri == redirectUri else {
            return try await oauthTokenErrorResponse(
                req: req,
                status: .badRequest,
                error: "invalid_grant",
                description: "Invalid or expired code"
            )
        }

        guard McpOAuthPkce.verifyS256(codeVerifier: verifier, codeChallenge: row.codeChallenge) else {
            return try await oauthTokenErrorResponse(req: req, status: .badRequest, error: "invalid_grant", description: "PKCE verification failed")
        }

        let project = try requireResolvedProject(req)
        guard row.$project.id == project.id! else {
            return try await oauthTokenErrorResponse(req: req, status: .badRequest, error: "invalid_grant", description: "Code does not match host")
        }

        row.consumedAt = Date()
        try await row.save(on: req.db)

        let rawToken = McpOAuthCrypto.randomToken(prefix: McpOAuthConstants.accessTokenPrefix)
        let tokenHash = McpOAuthCrypto.sha256Hex(rawToken)
        let access = McpOAuthAccessToken(
            tokenHash: tokenHash,
            projectId: row.$project.id,
            clientId: clientRow.id!,
            accountId: row.$account.id,
            subjectType: "user",
            scope: row.scope,
            expiresAt: Date().addingTimeInterval(McpOAuthConstants.accessTokenTTLSeconds)
        )
        try await access.save(on: req.db)

        let body = OAuthTokenSuccess(
            access_token: rawToken,
            token_type: "Bearer",
            expires_in: Int(McpOAuthConstants.accessTokenTTLSeconds),
            scope: row.scope
        )
        return try await body.encodeResponse(status: .ok, for: req)
    }

    private static func tokenClientCredentials(req: Request, form: TokenRequestForm) async throws -> Response {
        guard let clientId = form.client_id?.trimmingCharacters(in: .whitespacesAndNewlines), !clientId.isEmpty,
              let secret = form.client_secret?.trimmingCharacters(in: .whitespacesAndNewlines), !secret.isEmpty else {
            return try await oauthTokenErrorResponse(
                req: req,
                status: .badRequest,
                error: "invalid_request",
                description: "client_id and client_secret are required"
            )
        }
        guard let clientRow = try await McpOAuthClient.query(on: req.db)
            .filter(\.$publicClientId == clientId)
            .first(),
            clientRow.isActive,
            clientRow.isConfidential else {
            return try await oauthTokenErrorResponse(req: req, status: .badRequest, error: "invalid_client", description: "Unknown or invalid client")
        }
        guard let expected = clientRow.clientSecretHash,
              expected == McpOAuthCrypto.sha256Hex(secret) else {
            return try await oauthTokenErrorResponse(req: req, status: .unauthorized, error: "invalid_client", description: "Invalid client credentials")
        }
        guard clientRow.allowsGrant("client_credentials") else {
            return try await oauthTokenErrorResponse(
                req: req,
                status: .badRequest,
                error: "unauthorized_client",
                description: "Client cannot use client_credentials"
            )
        }

        let project = try requireResolvedProject(req)
        let rawToken = McpOAuthCrypto.randomToken(prefix: McpOAuthConstants.accessTokenPrefix)
        let tokenHash = McpOAuthCrypto.sha256Hex(rawToken)
        let access = McpOAuthAccessToken(
            tokenHash: tokenHash,
            projectId: project.id!,
            clientId: clientRow.id!,
            accountId: nil,
            subjectType: "service",
            scope: McpOAuthConstants.defaultScope,
            expiresAt: Date().addingTimeInterval(McpOAuthConstants.accessTokenTTLSeconds)
        )
        try await access.save(on: req.db)

        let body = OAuthTokenSuccess(
            access_token: rawToken,
            token_type: "Bearer",
            expires_in: Int(McpOAuthConstants.accessTokenTTLSeconds),
            scope: McpOAuthConstants.defaultScope
        )
        return try await body.encodeResponse(status: .ok, for: req)
    }

    // MARK: Helpers

    private static func requireOAuthEnabled() throws {
        guard AppEnvironment.mcpOAuthEnabled else {
            throw Abort(.notFound)
        }
    }

    private static func requireResolvedProject(_ req: Request) throws -> Project {
        guard let p = req.storage[ResolvedHostProjectKey.self], p.id != nil else {
            throw Abort(.forbidden, reason: "MCP OAuth requires a project host")
        }
        return p
    }

    private static func accountOwnsProject(accountId: UUID, projectId: UUID, db: Database) async throws -> Bool {
        guard let project = try await Project.query(on: db)
            .filter(\.$id == projectId)
            .filter(\.$account.$id == accountId)
            .first() else {
            return false
        }
        return project.id != nil
    }

    private static func tenantOrigin(forProjectId projectId: UUID, db: Database) async throws -> String? {
        guard let project = try await Project.find(projectId, on: db) else { return nil }
        return McpUrlBuilder.tenantOrigin(for: project)
    }

    private static func normalizeScope(_ raw: String) throws -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return McpOAuthConstants.defaultScope }
        let parts = s.split(separator: " ").map { String($0) }.filter { !$0.isEmpty }
        let allowed = Set([McpOAuthConstants.defaultScope])
        for p in parts where !allowed.contains(p) {
            throw Abort(.badRequest, reason: "Unsupported scope \(p)")
        }
        return McpOAuthConstants.defaultScope
    }

    private static func consentRedirectPath(pendingId: UUID) -> String {
        "/oauth/consent?pending=\(pendingId.uuidString)"
    }

    private static func redirectOAuthError(
        req: Request,
        redirectUri: String,
        state: String,
        error: String,
        description: String?
    ) throws -> Response {
        guard var c = URLComponents(string: redirectUri) else {
            throw Abort(.badRequest, reason: "Invalid redirect_uri")
        }
        var q = c.queryItems ?? []
        q.append(URLQueryItem(name: "error", value: error))
        q.append(URLQueryItem(name: "state", value: state))
        if let description {
            q.append(URLQueryItem(name: "error_description", value: description))
        }
        c.queryItems = q
        guard let url = c.url else {
            throw Abort(.badRequest, reason: "Invalid redirect")
        }
        return req.redirect(to: url.absoluteString, redirectType: .normal)
    }

    private static func oauthTokenErrorResponse(
        req: Request,
        status: HTTPStatus,
        error: String,
        description: String?
    ) async throws -> Response {
        let body = OAuthTokenError(error: error, error_description: description)
        return try await body.encodeResponse(status: status, for: req)
    }

    private static func htmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
