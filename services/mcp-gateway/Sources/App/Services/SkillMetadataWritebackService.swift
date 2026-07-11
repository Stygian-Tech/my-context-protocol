import Fluent
import Foundation
import Vapor

enum SkillMetadataWritebackService {
    struct Result: Content { let pull_request_url: String; let branch: String; let source_path: String }

    static func createDraftPullRequest(compiled: CompiledSkill, project: Project, app: Application, db: Database) async throws -> Result {
        guard let document = SkillRuntimeJSON.decode(CompiledSkillDocument.self, from: compiled.canonicalJson),
              !document.validation.clarificationRequired else { throw Abort(.conflict, reason: "Resolve all runtime clarification questions before write-back") }
        let path = document.source.path
        let allowedPath = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/-_."))
        guard !path.hasPrefix("/"), !path.split(separator: "/").contains(".."),
              path.unicodeScalars.allSatisfy(allowedPath.contains) else { throw Abort(.badRequest, reason: "Invalid source path") }
        guard let connection = try await RepoConnection.query(on: db).filter(\.$project.$id == project.id!).first() else { throw Abort(.conflict, reason: "No repository is connected") }
        let token = try await token(connection: connection, project: project, app: app, db: db)
        let owner = connection.repoOwner; let repo = connection.repoName; let base = connection.defaultBranch
        let api = "https://api.github.com/repos/\(owner)/\(repo)"
        let headers: HTTPHeaders = {
            var value = HTTPHeaders(); value.bearerAuthorization = .init(token: token)
            value.add(name: .accept, value: "application/vnd.github+json")
            value.add(name: "X-GitHub-Api-Version", value: "2022-11-28")
            return value
        }()

        struct RefResponse: Content { struct Object: Content { let sha: String }; let object: Object }
        let refResponse = try await app.client.get(URI(string: "\(api)/git/ref/heads/\(base)"), headers: headers)
        guard refResponse.status == .ok else { throw githubError(refResponse, action: "read the default branch") }
        let baseSha = try refResponse.content.decode(RefResponse.self).object.sha
        let safeId = document.id.prefix(32).map { $0.isLetter || $0.isNumber || $0 == "-" ? String($0) : "-" }.joined()
        let branch = "mcp/skill-metadata-\(safeId)-\(Int(Date().timeIntervalSince1970))"
        struct CreateRef: Content { let ref: String; let sha: String }
        let createRef = try await app.client.post(URI(string: "\(api)/git/refs"), headers: headers) { request in
            try request.content.encode(CreateRef(ref: "refs/heads/\(branch)", sha: baseSha))
        }
        guard createRef.status == .created else { throw githubError(createRef, action: "create the metadata branch") }

        struct FileResponse: Content { let sha: String }
        let encodedPath = path.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
        let fileResponse = try await app.client.get(URI(string: "\(api)/contents/\(encodedPath)?ref=\(base)"), headers: headers)
        guard fileResponse.status == .ok else { throw githubError(fileResponse, action: "read the skill source") }
        let fileSha = try fileResponse.content.decode(FileResponse.self).sha
        let content = frontmatter(document) + "\n" + document.instructions.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        struct UpdateFile: Content { let message: String; let content: String; let branch: String; let sha: String }
        let update = try await app.client.put(URI(string: "\(api)/contents/\(encodedPath)"), headers: headers) { request in
            try request.content.encode(UpdateFile(
                message: "chore: add portable runtime metadata for \(document.id)",
                content: Data(content.utf8).base64EncodedString(), branch: branch, sha: fileSha
            ))
        }
        guard update.status == .ok || update.status == .created else { throw githubError(update, action: "write skill metadata") }

        struct CreatePull: Content { let title: String; let head: String; let base: String; let body: String; let draft: Bool }
        struct PullResponse: Content { let html_url: String }
        let pull = try await app.client.post(URI(string: "\(api)/pulls"), headers: headers) { request in
            try request.content.encode(CreatePull(
                title: "Add portable runtime metadata for \(document.id)", head: branch, base: base,
                body: "Generated from validated MyContextProtocol deployment metadata. The database override remains active until this metadata is merged and synced.", draft: true
            ))
        }
        guard pull.status == .created else { throw githubError(pull, action: "open the draft pull request") }
        let url = try pull.content.decode(PullResponse.self).html_url
        if let override = try await SkillRuntimeOverride.query(on: db).filter(\.$project.$id == project.id!).filter(\.$skillId == document.id).first() {
            override.writebackPrUrl = url; try await override.save(on: db)
        }
        return .init(pull_request_url: url, branch: branch, source_path: path)
    }

    private static func token(connection: RepoConnection, project: Project, app: Application, db: Database) async throws -> String {
        var oauth: String?
        if let encrypted = connection.tokenEncrypted { oauth = try? TokenEncryption.decrypt(encrypted) }
        if oauth == nil { try await project.$account.load(on: db); if let encrypted = project.account.githubTokenEncrypted { oauth = try? TokenEncryption.decrypt(encrypted) } }
        if let installation = connection.githubInstallationId {
            return try await GitHubAppInstallationTokenService.bearerTokenForGitHubREST(installationId: installation, oauthToken: oauth ?? "", client: app.client, logger: app.logger, db: db)
        }
        guard let oauth, !oauth.isEmpty else { throw Abort(.unauthorized, reason: "Repository write access is not configured") }
        return oauth
    }

    private static func frontmatter(_ document: CompiledSkillDocument) -> String {
        func quoted(_ value: String) -> String { String(data: try! JSONEncoder().encode(value), encoding: .utf8)! }
        func list(_ values: [String]) -> String { "[" + values.map(quoted).joined(separator: ", ") + "]" }
        var lines = ["---", "name: \(quoted(document.id))", "description: \(quoted(document.description))", "kind: \(document.kind.rawValue)", "scope: \(document.scope.rawValue)", "enforcement: \(document.enforcement.rawValue)", "priority: \(document.priority)", "version: \(quoted(document.version))", "activation:", "  mode: \(document.activation.mode.rawValue)", "  intents: \(list(document.activation.intents))", "  events: \(list(document.activation.events))", "  tags: \(list(document.activation.tags))", "  examples: \(list(document.activation.examples))"]
        if !document.requires.isEmpty {
            lines.append("requires:")
            for requirement in document.requires { lines.append("  - capability: \(quoted(requirement.capability))"); lines.append("    required: \(requirement.required)"); lines.append("    on_missing: \(requirement.onMissing.rawValue)") }
        }
        lines.append("conflictsWith: \(list(document.conflictsWith))"); lines.append("---")
        return lines.joined(separator: "\n")
    }

    private static func githubError(_ response: ClientResponse, action: String) -> Abort {
        let permissions = response.status == .forbidden ? " Ensure the GitHub App has Contents: write and Pull requests: write permissions." : ""
        return Abort(.badGateway, reason: "GitHub could not \(action) (HTTP \(response.status.code)).\(permissions)")
    }
}
