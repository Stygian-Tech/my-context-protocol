import Foundation
import Vapor

private struct GHUserRepoRow: Decodable {
    let full_name: String
    let name: String
    let owner: GHOwnerLoginRow
    let default_branch: String?
    let isPrivate: Bool

    enum CodingKeys: String, CodingKey {
        case full_name, name, owner, default_branch
        case isPrivate = "private"
    }
}

private struct GHOwnerLoginRow: Decodable {
    let login: String
}

enum GitHubRepositoriesService {
    /// Fetches repositories the OAuth token can access (`GET /user/repos`), following `Link: rel=next` up to `maxPages`.
    static func listUserRepositories(
        token: String,
        client: Client,
        logger: Logger,
        maxPages: Int = 10
    ) async throws -> [GithubRepoListItem] {
        var collected: [GithubRepoListItem] = []
        var nextURL: String? =
            "https://api.github.com/user/repos?per_page=100&sort=updated&affiliation=owner,collaborator,organization_member"
        var page = 0

        while let urlString = nextURL, page < maxPages {
            page += 1
            let uri = URI(string: urlString)

            let response = try await client.get(uri) { req in
                req.headers.bearerAuthorization = BearerAuthorization(token: token)
                req.headers.add(name: "Accept", value: "application/vnd.github+json")
                req.headers.add(name: "X-GitHub-Api-Version", value: "2022-11-28")
                req.headers.add(name: "User-Agent", value: "MyContextProtocol/1")
            }

            guard response.status == .ok else {
                let snippet = response.body.map { String(buffer: $0).prefix(300) } ?? ""
                logger.warning("GitHub user/repos: HTTP \(response.status.code) \(snippet)")
                throw Abort(.badGateway, reason: "Could not load repositories from GitHub.")
            }

            guard let body = response.body else { break }
            let data = Data(buffer: body)
            let rows: [GHUserRepoRow]
            do {
                rows = try JSONDecoder().decode([GHUserRepoRow].self, from: data)
            } catch {
                logger.warning("GitHub user/repos decode failed: \(error)")
                throw Abort(.badGateway, reason: "Could not parse repository list from GitHub.")
            }

            for row in rows {
                collected.append(
                    GithubRepoListItem(
                        full_name: row.full_name,
                        owner_login: row.owner.login,
                        name: row.name,
                        default_branch: row.default_branch ?? "main",
                        is_private: row.isPrivate
                    )
                )
            }

            nextURL = response.headers.links?.first { $0.relation == .next }?.uri
        }

        return collected
    }
}
