import Foundation
import Vapor

enum GitHubWebhookService {
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

        let url = "https://api.github.com/repos/\(owner)/\(repo)/hooks"
        let response = try await client.post(URI(string: url)) { req in
            try req.content.encode(body)
            req.headers.bearerAuthorization = BearerAuthorization(token: token)
            req.headers.add(name: "Accept", value: "application/vnd.github+json")
            req.headers.add(name: "X-GitHub-Api-Version", value: "2022-11-28")
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
        let url = "https://api.github.com/repos/\(owner)/\(repo)/hooks/\(webhookId)"
        let response = try await client.delete(URI(string: url)) { req in
            req.headers.bearerAuthorization = BearerAuthorization(token: token)
            req.headers.add(name: "Accept", value: "application/vnd.github+json")
            req.headers.add(name: "X-GitHub-Api-Version", value: "2022-11-28")
        }
        if response.status != .noContent && response.status != .notFound {
            let body = response.body.map { String(buffer: $0) } ?? ""
            throw GitHubWebhookError.deleteFailed(status: Int(response.status.code), body: body)
        }
    }

    /// Verifies the token can access the repo (GET /repos/:owner/:repo).
    static func verifyRepoAccess(
        owner: String,
        repo: String,
        token: String,
        client: Client
    ) async throws {
        let url = "https://api.github.com/repos/\(owner)/\(repo)"
        let response = try await client.get(URI(string: url)) { req in
            req.headers.bearerAuthorization = BearerAuthorization(token: token)
            req.headers.add(name: "Accept", value: "application/vnd.github+json")
        }
        guard response.status == .ok else {
            throw GitHubWebhookError.repoAccessDenied(status: Int(response.status.code))
        }
    }
}

enum GitHubWebhookError: Error {
    case repoAccessDenied(status: Int)
    case createFailed(status: Int, body: String)
    case deleteFailed(status: Int, body: String)
}
