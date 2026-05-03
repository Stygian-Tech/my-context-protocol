import Fluent
import Foundation

/// `request_logs.client_id` stores opaque client references. API key traffic uses a stable ID-based
/// token so renames do not require rewriting historical rows; list endpoints resolve to the current
/// display label (`name` or key prefix).
enum RequestLogClientResolver {
    static let apiKeyReferencePrefix = "apikey:"

    /// Persisted value for MCP requests authenticated with an API key.
    static func storedApiKeyReference(apiKeyId: UUID) -> String {
        "\(apiKeyReferencePrefix)\(apiKeyId.uuidString)"
    }

    /// API key UUIDs referenced by log rows (deduplicated).
    static func apiKeyIds(from logs: [RequestLog]) -> [UUID] {
        var seen = Set<UUID>()
        var out: [UUID] = []
        for log in logs {
            guard let s = log.clientId, s.hasPrefix(apiKeyReferencePrefix) else { continue }
            let rest = String(s.dropFirst(apiKeyReferencePrefix.count))
            guard let id = UUID(uuidString: rest), seen.insert(id).inserted else { continue }
            out.append(id)
        }
        return out
    }

    /// Human-readable label for dashboards / API responses. Non–API-key rows (e.g. OAuth) pass through unchanged.
    static func displayLabel(stored: String?, keysById: [UUID: ApiKey]) -> String? {
        guard let stored, !stored.isEmpty else { return nil }
        guard stored.hasPrefix(apiKeyReferencePrefix) else { return stored }
        let rest = String(stored.dropFirst(apiKeyReferencePrefix.count))
        guard let id = UUID(uuidString: rest) else { return stored }
        guard let key = keysById[id] else {
            return "API key (removed)"
        }
        if let name = key.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return key.keyPrefix
    }
}
