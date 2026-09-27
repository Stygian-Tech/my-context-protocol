import Fluent
import Foundation
import Vapor

struct SkillPackageFileDescriptor: Codable, Sendable {
    let path: String
    let checksum: String
    let mediaType: String
    let byteCount: Int
    let resourceUri: String
}

struct SkillPackageResourceReference: Equatable, Sendable {
    let skillId: String
    let path: String?
    let version: String?
}

enum SkillPackageResourceService {
    static func normalize(relativePath raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 1_024,
              !trimmed.hasPrefix("/"), !trimmed.hasPrefix("~"), !trimmed.contains("\\") else {
            throw Abort(.badRequest, reason: "path must be a safe package-relative path")
        }
        let decoded = trimmed.removingPercentEncoding ?? trimmed
        guard decoded == trimmed else {
            throw Abort(.badRequest, reason: "path must not contain percent-encoded traversal or separators")
        }
        let components = trimmed.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value != 0x7f } }) else {
            throw Abort(.badRequest, reason: "path must be a safe package-relative path")
        }
        return components.joined(separator: "/")
    }

    static func uri(skillId: String, path: String? = nil, version: String? = nil) -> String {
        var value = "ctx://skill/\(encodeComponent(skillId))"
        if let path {
            value += "/file/" + path.split(separator: "/").map { encodeComponent(String($0)) }.joined(separator: "/")
        }
        if let version {
            var queryAllowed = CharacterSet.urlQueryAllowed
            queryAllowed.remove(charactersIn: "&=+#%")
            guard let encodedVersion = version.addingPercentEncoding(withAllowedCharacters: queryAllowed) else {
                return value
            }
            value += "?version=\(encodedVersion)"
        }
        return value
    }

    static func parse(uri raw: String) throws -> SkillPackageResourceReference? {
        guard raw.hasPrefix("ctx://skill/") else { return nil }
        guard !raw.contains("#") else { throw Abort(.badRequest, reason: "Invalid skill resource URI") }
        let queryParts = raw.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let resource = String(queryParts[0])
        let version: String?
        if queryParts.count == 2 {
            let query = String(queryParts[1])
            guard query.hasPrefix("version="), !query.dropFirst("version=".count).contains("&"),
                  let decodedVersion = String(query.dropFirst("version=".count)).removingPercentEncoding else {
                throw Abort(.badRequest, reason: "Invalid skill resource URI")
            }
            let trimmedVersion = decodedVersion.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedVersion.isEmpty, trimmedVersion.count <= 512 else {
                throw Abort(.badRequest, reason: "Invalid skill resource URI")
            }
            version = trimmedVersion
        } else {
            version = nil
        }
        let remainder = String(resource.dropFirst("ctx://skill/".count))
        let pieces = remainder.components(separatedBy: "/file/")
        guard pieces.count == 1 || pieces.count == 2,
              let skillId = pieces[0].removingPercentEncoding,
              !skillId.isEmpty, !skillId.contains("/"), !skillId.contains("\\") else {
            throw Abort(.badRequest, reason: "Invalid skill resource URI")
        }
        if pieces.count == 1 { return .init(skillId: skillId, path: nil, version: version) }
        let encodedPath = pieces[1]
        let decodedComponents = try encodedPath.split(separator: "/", omittingEmptySubsequences: false).map { component -> String in
            guard let decoded = String(component).removingPercentEncoding,
                  !decoded.contains("/"), !decoded.contains("\\") else {
                throw Abort(.badRequest, reason: "Invalid skill resource URI")
            }
            return decoded
        }
        return .init(
            skillId: skillId,
            path: try normalize(relativePath: decodedComponents.joined(separator: "/")),
            version: version
        )
    }

    static func activeCompiledSkill(
        projectId: UUID,
        skillId: String,
        version: String? = nil,
        db: Database
    ) async throws -> (CompiledSkill, CompiledSkillDocument) {
        guard let releaseId = try await MCPCatalogService.activeReleaseId(projectId: projectId, db: db) else {
            throw Abort(.notFound, reason: "The project has no active release")
        }
        var query = CompiledSkill.query(on: db)
            .filter(\.$release.$id == releaseId)
            .filter(\.$status == "ready")
            .filter(\.$skillId == skillId)
        if let version { query = query.filter(\.$version == version) }
        guard let row = try await query.first(),
              let document = SkillRuntimeJSON.decode(CompiledSkillDocument.self, from: row.canonicalJson) else {
            throw Abort(.notFound, reason: "The requested skill or version is not active in this project")
        }
        return (row, document)
    }

    static func files(
        for compiled: CompiledSkill,
        skillId: String,
        version: String,
        db: Database
    ) async throws -> [SkillPackageFileDescriptor] {
        let rows = try await SkillPackageFile.query(on: db)
            .filter(\.$skillPackage.$id == compiled.$skillPackage.id)
            .sort(\.$path)
            .all()
        return rows.map {
            SkillPackageFileDescriptor(
                path: $0.path,
                checksum: $0.checksum,
                mediaType: $0.contentType ?? "application/octet-stream",
                byteCount: $0.byteCount,
                resourceUri: uri(skillId: skillId, path: $0.path, version: version)
            )
        }
    }

    static func file(compiled: CompiledSkill, path: String, db: Database) async throws -> SkillPackageFile {
        guard let row = try await SkillPackageFile.query(on: db)
            .filter(\.$skillPackage.$id == compiled.$skillPackage.id)
            .filter(\.$path == path)
            .first() else {
            throw Abort(.notFound, reason: "Package file not found")
        }
        return row
    }

    private static func encodeComponent(_ raw: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#%\\")
        return raw.addingPercentEncoding(withAllowedCharacters: allowed) ?? raw
    }
}
