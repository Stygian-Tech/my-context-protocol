import Fluent

/// Rolls up `RequestLog` rows that tagged an MCP tool/resource/prompt invocation.
enum CapabilityUsageAggregation {
    private struct Key: Hashable {
        let kind: String
        let key: String
    }

    static func breakdown(from logs: [RequestLog]) -> [DashboardCapabilityUsage] {
        var counts: [Key: Int] = [:]
        var successes: [Key: Int] = [:]
        for log in logs {
            guard let kindRaw = log.mcpCapabilityKind?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !kindRaw.isEmpty,
                  let keyRaw = log.mcpCapabilityKey?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !keyRaw.isEmpty else {
                continue
            }
            let k = Key(kind: kindRaw, key: keyRaw)
            counts[k, default: 0] += 1
            if log.countsAsSuccessfulRequestMetric {
                successes[k, default: 0] += 1
            }
        }
        return counts.map { entry in
            DashboardCapabilityUsage(
                kind: entry.key.kind,
                key: entry.key.key,
                invocations_last_7d: entry.value,
                successful_last_7d: successes[entry.key] ?? 0
            )
        }
        .sorted { lhs, rhs in
            if lhs.invocations_last_7d != rhs.invocations_last_7d {
                return lhs.invocations_last_7d > rhs.invocations_last_7d
            }
            if lhs.kind != rhs.kind { return lhs.kind < rhs.kind }
            return lhs.key < rhs.key
        }
    }
}
