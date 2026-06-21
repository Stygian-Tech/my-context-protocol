import Foundation
import Vapor

enum GitHubWebhookService {
    /// GitHub rejects requests without a non-empty `User-Agent` (HTTP 403).
    private static let githubUserAgent = "MyContextProtocol/1"

    /// Verifies the account has access to the repo and creates a webhook.
    /// Returns (webhookId, webhookSecret) or throws.
    static func createWebhook(
        owner: String,
        repo: String,
        token: String,
        baseURL: String,
        client: Client
    ) async throws -> (webhookId: String, webhookSecret: String) {
        let webhookURL = baseURL.hasSuffix("/") ? baseURL + "webhooks/github" : baseURL + "/webhooks/github"
        let secretBytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        let secretHex = secretBytes.map { String(format: "%02x", $0) }.joined()

        struct HookConfig: Content {
            let url: String
            let content_type: String
            let secret: String
        }
        struct HookBody: Content {
            let name: String
            let config: HookConfig
            let events: [String]
        }
        struct HookResponse: Content {
            let id: Int
        }

        let body = HookBody(
            name: "web",
            config: HookConfig(
                url: webhookURL,
                content_type: "json",
                secret: secretHex
            ),
            events: ["push"]
        )

        let url = "https://api.github.com/repos/\(RepoFetcher.pathSegmentEscape(owner))/\(RepoFetcher.pathSegmentEscape(repo))/hooks"
        let response = try await client.post(URI(string: url)) { req in
            try req.content.encode(body)
            req.headers.bearerAuthorization = BearerAuthorization(token: token)
            req.headers.add(name: "Accept", value: "application/vnd.github+json")
            req.headers.add(name: "X-GitHub-Api-Version", value: "2022-11-28")
            req.headers.add(name: "User-Agent", value: Self.githubUserAgent)
        }

        guard response.status == .created else {
            let body = response.body.map { String(buffer: $0) } ?? ""
            throw GitHubWebhookError.createFailed(status: Int(response.status.code), body: body)
        }

        let hookResp = try response.content.decode(HookResponse.self)
        return (String(hookResp.id), secretHex)
    }

    /// Deletes an existing webhook. Call before creating a new one when reconnecting.
    static func deleteWebhook(
        owner: String,
        repo: String,
        webhookId: String,
        token: String,
        client: Client
    ) async throws {
        let url = "https://api.github.com/repos/\(RepoFetcher.pathSegmentEscape(owner))/\(RepoFetcher.pathSegmentEscape(repo))/hooks/\(RepoFetcher.pathSegmentEscape(webhookId))"
        let response = try await client.delete(URI(string: url)) { req in
            req.headers.bearerAuthorization = BearerAuthorization(token: token)
            req.headers.add(name: "Accept", value: "application/vnd.github+json")
            req.headers.add(name: "X-GitHub-Api-Version", value: "2022-11-28")
            req.headers.add(name: "User-Agent", value: Self.githubUserAgent)
        }
        if response.status != .noContent && response.status != .notFound {
            let body = response.body.map { String(buffer: $0) } ?? ""
            throw GitHubWebhookError.deleteFailed(status: Int(response.status.code), body: body)
        }
    }

    /// Verifies access to the repo (`GET /repos/:owner/:repo`).
    /// When `userFallbackToken` is set (Pro path: primary is an installation token), a 403/404 from GitHub
    /// may mean the repository is not part of the installation; we re-check with the user token to surface that.
    static func verifyRepoAccess(
        owner: String,
        repo: String,
        primaryToken: String,
        userFallbackToken: String?,
        client: Client,
        logger: Logger
    ) async throws {
        let primaryCode = try await gitHubRepoGetStatus(owner: owner, repo: repo, token: primaryToken, client: client)
        if primaryCode == 200 { return }

        if let fallback = userFallbackToken, !fallback.isEmpty, primaryCode == 403 || primaryCode == 404 {
            let fbCode = try await gitHubRepoGetStatus(owner: owner, repo: repo, token: fallback, client: client)
            if fbCode == 200 {
                logger.warning(
                    "GitHub repo \(owner)/\(repo): installation token denied (HTTP \(primaryCode)) but user OAuth can access; repo likely not in App installation scope"
                )
                throw GitHubWebhookError.repoNotIncludedInAppInstallation
            }
        }

        throw GitHubWebhookError.repoAccessDenied(status: primaryCode)
    }

    private static func gitHubRepoGetStatus(
        owner: String,
        repo: String,
        token: String,
        client: Client
    ) async throws -> Int {
        let url = "https://api.github.com/repos/\(RepoFetcher.pathSegmentEscape(owner))/\(RepoFetcher.pathSegmentEscape(repo))"
        let response = try await client.get(URI(string: url)) { req in
            req.headers.bearerAuthorization = BearerAuthorization(token: token)
            req.headers.add(name: "Accept", value: "application/vnd.github+json")
            req.headers.add(name: "X-GitHub-Api-Version", value: "2022-11-28")
            req.headers.add(name: "User-Agent", value: "MyContextProtocol/1")
        }
        return Int(response.status.code)
    }
}

enum GitHubWebhookError: Error {
    /// Installation (or primary) token cannot read the repo, and user token was not tried or also failed.
    case repoAccessDenied(status: Int)
    /// User OAuth can read the repo but the GitHub App installation does not include it (`Resource not accessible by integration`).
    case repoNotIncludedInAppInstallation
    case createFailed(status: Int, body: String)
    case deleteFailed(status: Int, body: String)
}

extension GitHubWebhookError: AbortError {
    var status: HTTPResponseStatus {
        switch self {
        case .repoAccessDenied(let code):
            if code == 404 { return .notFound }
            if code == 403 { return .forbidden }
            return .badGateway
        case .repoNotIncludedInAppInstallation:
            return .unprocessableEntity
        case .createFailed(let code, _):
            if code == 403 || code == 401 { return .forbidden }
            if code == 404 { return .notFound }
            if code == 422 { return .unprocessableEntity }
            return .badGateway
        case .deleteFailed:
            return .badGateway
        }
    }

    var reason: String {
        switch self {
        case .repoAccessDenied(let code):
            return "GitHub API returned HTTP \(code) for this repository. Confirm the owner/repo name and that your GitHub login still has access."
        case .repoNotIncludedInAppInstallation:
            return "Your GitHub account can access this repository, but the GitHub App installation does not include it. On github.com: Settings → Integrations → Applications → Installed GitHub Apps → configure this app → Repository access → add this repository (or “All repositories”), then try connecting again."
        case .createFailed(let code, let body):
            let snippet = String(body.prefix(400)).trimmingCharacters(in: .whitespacesAndNewlines)
            if snippet.isEmpty {
                return "Could not create repository webhook on GitHub (HTTP \(code))."
            }
            return "Could not create repository webhook on GitHub (HTTP \(code)): \(snippet)"
        case .deleteFailed(let code, let body):
            return "Could not delete previous webhook on GitHub (HTTP \(code)): \(String(body.prefix(200)))"
        }
    }
}
