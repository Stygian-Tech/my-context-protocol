import Fluent
import Foundation
import Vapor
import Yams

enum SkillMetadataWritebackService {
    struct Result: Content { let pull_request_url: String; let branch: String; let source_path: String }

    static func createDraftPullRequest(compiled: CompiledSkill, project: Project, app: Application, db: Database) async throws -> Result {
        guard let document = SkillRuntimeJSON.decode(CompiledSkillDocument.self, from: compiled.canonicalJson),
              !document.validation.clarificationRequired else { throw Abort(.conflict, reason: "Resolve all runtime clarification questions before write-back") }
        let path = ".mycontext/skills.yaml"
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

        struct FileResponse: Content { let sha: String; let content: String?; let encoding: String? }
        let encodedPath = path.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
        let fileResponse = try await app.client.get(URI(string: "\(api)/contents/\(encodedPath)?ref=\(base)"), headers: headers)
        guard fileResponse.status == .ok || fileResponse.status == .notFound else {
            throw githubError(fileResponse, action: "read the skill policy sidecar")
        }
        let existing = fileResponse.status == .ok ? try fileResponse.content.decode(FileResponse.self) : nil
        let currentYaml: String?
        if let existing {
            guard existing.encoding == nil || existing.encoding == "base64",
                  let encoded = existing.content else {
                throw Abort(.conflict, reason: "Existing skill policy sidecar could not be decoded safely")
            }
            let compact = encoded.replacingOccurrences(of: "\n", with: "")
            guard let data = Data(base64Encoded: compact),
                  let decoded = String(data: data, encoding: .utf8) else {
                throw Abort(.conflict, reason: "Existing skill policy sidecar is not valid base64 UTF-8")
            }
            currentYaml = decoded
        } else {
            currentYaml = nil
        }
        let content = try mergedSidecar(existing: currentYaml, document: document, exposure: compiled.exposureType)
        struct UpdateFile: Content { let message: String; let content: String; let branch: String; let sha: String? }
        let update = try await app.client.put(URI(string: "\(api)/contents/\(encodedPath)"), headers: headers) { request in
            try request.content.encode(UpdateFile(
                message: "chore: update portable runtime policy for \(document.id)",
                content: Data(content.utf8).base64EncodedString(), branch: branch, sha: existing?.sha
            ))
        }
        guard update.status == .ok || update.status == .created else { throw githubError(update, action: "write skill metadata") }

        struct CreatePull: Content { let title: String; let head: String; let base: String; let body: String; let draft: Bool }
        struct PullResponse: Content { let html_url: String }
        let pull = try await app.client.post(URI(string: "\(api)/pulls"), headers: headers) { request in
            try request.content.encode(CreatePull(
                title: "Update portable runtime policy for \(document.id)", head: branch, base: base,
                body: "Updates `.mycontext/skills.yaml` from validated MyContextProtocol deployment metadata. `SKILL.md` remains the package's authored source and is not reconstructed.", draft: true
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

    static func mergedSidecar(existing: String?, document: CompiledSkillDocument, exposure: String = "resource") throws -> String {
        var root = (try existing.flatMap { try load(yaml: $0) } as? [String: Any]) ?? [:]
        var skills = root["skills"] as? [String: Any] ?? [:]
        let metadata = SkillRuntimeOverridePatch(
            exposure: exposure,
            kind: document.kind,
            scope: document.scope,
            activation: document.activation,
            enforcement: document.enforcement,
            priority: document.priority,
            requires: document.requires,
            avoidWhen: document.avoidWhen,
            conflictsWith: document.conflictsWith,
            version: document.version,
            lifecycle: document.lifecycle
        )
        let policy = SkillSourcePolicy(baseChecksum: document.source.checksum, metadata: metadata)
        let encoded = try JSONEncoder().encode(policy)
        let object = try JSONSerialization.jsonObject(with: encoded)
        guard let generated = yamlCompatible(object) as? [String: Any] else {
            throw Abort(.internalServerError, reason: "Generated skill policy was not an object")
        }
        let existingSkill = skills[document.id] as? [String: Any] ?? [:]
        skills[document.id] = merge(existing: existingSkill, generated: generated)
        root["version"] = root["version"] ?? 1
        root["skills"] = skills
        return try dump(object: root, sortKeys: true) + "\n"
    }

    private static func yamlCompatible(_ value: Any) -> Any {
        if let string = value as? NSString { return string as String }
        if let number = value as? NSNumber {
            if String(cString: number.objCType) == "c" { return number.boolValue }
            let double = number.doubleValue
            return double.rounded() == double ? number.intValue : double
        }
        if let dictionary = value as? [String: Any] {
            return dictionary.mapValues(yamlCompatible)
        }
        if let array = value as? [Any] {
            return array.map(yamlCompatible)
        }
        if let dictionary = value as? NSDictionary {
            var result: [String: Any] = [:]
            for (key, item) in dictionary {
                if let key = key as? String { result[key] = yamlCompatible(item) }
            }
            return result
        }
        if let array = value as? NSArray {
            return array.map(yamlCompatible)
        }
        return value
    }

    private static func merge(existing: [String: Any], generated: [String: Any]) -> [String: Any] {
        var result = existing
        for (key, value) in generated {
            if let generatedObject = value as? [String: Any],
               let existingObject = result[key] as? [String: Any] {
                result[key] = merge(existing: existingObject, generated: generatedObject)
            } else {
                result[key] = value
            }
        }
        return result
    }

    private static func githubError(_ response: ClientResponse, action: String) -> Abort {
        let permissions = response.status == .forbidden ? " Ensure the GitHub App has Contents: write and Pull requests: write permissions." : ""
        return Abort(.badGateway, reason: "GitHub could not \(action) (HTTP \(response.status.code)).\(permissions)")
    }
}
