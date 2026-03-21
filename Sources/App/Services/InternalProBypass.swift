import Foundation
import Vapor

/// Env-configured allowlist so internal accounts get Pro features without Stripe.
/// - `INTERNAL_PRO_GITHUB_LOGINS` — comma-separated GitHub usernames (case-insensitive).
/// - `INTERNAL_PRO_GITHUB_IDS` — comma-separated numeric `github_id` values.
enum InternalProBypass {
    static func matches(login: String, githubId: Int64) -> Bool {
        let logins = parseStringList(Environment.get("INTERNAL_PRO_GITHUB_LOGINS"))
        if !logins.isEmpty, logins.contains(login.lowercased()) {
            return true
        }
        let ids = parseIdList(Environment.get("INTERNAL_PRO_GITHUB_IDS"))
        if !ids.isEmpty, ids.contains(githubId) {
            return true
        }
        return false
    }

    private static func parseStringList(_ raw: String?) -> Set<String> {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return []
        }
        return Set(
            raw.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
    }

    private static func parseIdList(_ raw: String?) -> Set<Int64> {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return []
        }
        var out = Set<Int64>()
        for part in raw.split(separator: ",") {
            let t = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if let v = Int64(t) { out.insert(v) }
        }
        return out
    }
}
