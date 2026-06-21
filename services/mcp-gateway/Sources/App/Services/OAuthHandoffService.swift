import Fluent
import Foundation
import SQLKit
import Vapor

enum OAuthHandoffService {
    private static let ttl: TimeInterval = 300

    private static func makeToken() -> String {
        var rnd = [UInt8](repeating: 0, count: 32)
        for i in rnd.indices {
            rnd[i] = UInt8.random(in: 0 ... 255)
        }
        return rnd.map { String(format: "%02x", $0) }.joined()
    }

    static func issue(accountId: UUID, on db: Database) async throws -> String {
        let token = makeToken()
        let row = OAuthHandoffToken(
            token: token,
            accountId: accountId,
            expiresAt: Date().addingTimeInterval(ttl)
        )
        row.createdAt = Date()
        try await row.save(on: db)
        return token
    }

    /// Returns account id if token was valid (and deletes the row).
    static func consume(_ token: String, on db: Database) async throws -> UUID? {
        if let sql = db as? any SQLDatabase {
            let row = try await sql.delete(from: OAuthHandoffToken.schema)
                .where(SQLColumn("token"), .equal, SQLBind(token))
                .where(SQLColumn("expires_at"), .greaterThan, SQLBind(Date()))
                .returning(SQLColumn("account_id"))
                .first()
            return try row?.decode(column: "account_id", as: UUID.self)
        }

        guard let row = try await OAuthHandoffToken.query(on: db).filter(\.$token == token).first() else {
            return nil
        }
        let accountId = row.accountId
        if row.expiresAt <= Date() {
            try await row.delete(on: db)
            return nil
        }
        try await row.delete(on: db)
        return accountId
    }
}
