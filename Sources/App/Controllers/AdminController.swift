import Fluent
import Vapor

/// Aggregate-only platform stats (no per-user or per-project payloads).
struct AdminPlatformMetricsResponse: Content {
    let total_users: Int
    let total_projects: Int
    let total_mcp_calls: Int
}

/// Lookup result: account id and current flags only (no login, email, or project names).
struct AdminLookupResponse: Content {
    let account_id: String
    let is_admin: Bool
    let paywall_bypass: Bool
}

struct AdminLookupRequest: Content {
    var github_login: String?
    /// String avoids JS number precision issues for large GitHub numeric ids.
    var github_id: String?
    var email: String?
}

struct AdminAccountFlagsRequest: Content {
    let account_id: UUID
    var is_admin: Bool?
    var paywall_bypass: Bool?
}

enum AdminController {
    static func platformMetrics(req: Request) async throws -> AdminPlatformMetricsResponse {
        AdminPlatformMetricsResponse(
            total_users: Int(try await Account.query(on: req.db).count()),
            total_projects: Int(try await Project.query(on: req.db).count()),
            total_mcp_calls: Int(try await RequestLog.query(on: req.db).count())
        )
    }

    static func lookup(req: Request) async throws -> AdminLookupResponse {
        let body = try req.content.decode(AdminLookupRequest.self)
        let hasLogin = body.github_login.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false
        let hasEmail = body.email.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false
        let rawGid = body.github_id?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasGidField = !(rawGid ?? "").isEmpty
        let gidParsed: Int64? = {
            guard let rawGid, !rawGid.isEmpty else { return nil }
            return Int64(rawGid)
        }()
        if hasGidField, gidParsed == nil {
            throw Abort(.badRequest, reason: "Invalid github_id")
        }
        let hasId = gidParsed != nil

        let n = (hasLogin ? 1 : 0) + (hasEmail ? 1 : 0) + (hasId ? 1 : 0)
        guard n == 1 else {
            throw Abort(.badRequest, reason: "Provide exactly one of github_login, github_id, or email")
        }

        let account: Account?
        if hasLogin, let raw = body.github_login {
            let login = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            account = try await Account.query(on: req.db).filter(\.$login == login).first()
        } else if hasId, let gid = gidParsed {
            account = try await Account.query(on: req.db).filter(\.$githubId == gid).first()
        } else if hasEmail, let raw = body.email {
            let email = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            account = try await Account.query(on: req.db).filter(\.$email == email).first()
        } else {
            account = nil
        }

        guard let acct = account, let id = acct.id else {
            throw Abort(.notFound, reason: "Account not found")
        }

        return AdminLookupResponse(
            account_id: id.uuidString,
            is_admin: acct.isAdmin,
            paywall_bypass: acct.paywallBypass
        )
    }

    static func updateFlags(req: Request) async throws -> HTTPStatus {
        let body = try req.content.decode(AdminAccountFlagsRequest.self)
        let hasAdmin = body.is_admin != nil
        let hasBypass = body.paywall_bypass != nil
        guard hasAdmin || hasBypass else {
            throw Abort(.badRequest, reason: "Set at least one of is_admin or paywall_bypass")
        }

        guard let account = try await Account.find(body.account_id, on: req.db) else {
            throw Abort(.notFound, reason: "Account not found")
        }

        if let v = body.is_admin {
            if v == false,
               let sid = req.session.data["accountId"],
               let selfId = UUID(uuidString: sid),
               selfId == body.account_id {
                throw Abort(.badRequest, reason: "Cannot remove your own admin access")
            }
            account.isAdmin = v
        }
        if let v = body.paywall_bypass {
            account.paywallBypass = v
        }
        try await account.save(on: req.db)
        return .noContent
    }

    // MARK: - Analytics (hourly rollup)

    static func adminDashboardTimeseries(req: Request) async throws -> AdminDashboardTimeseriesResponse {
        try await AdminAnalyticsTimeseriesService.adminDashboardTimeseries(
            db: req.db,
            rangeKey: req.query[String.self, at: "range"]
        )
    }

    static func rollupRefresh(req: Request) async throws -> HTTPStatus {
        try await AdminAnalyticsRollupService.refresh(db: req.db, logger: req.logger)
        return .noContent
    }
}
