import Vapor

struct SkillUsageCounts: Content, Sendable {
    var surfaced = 0
    var instructions_delivered = 0
    var supporting_file_read = 0
    var resolver_selected = 0
    var resolver_suggested = 0
    var resolver_excluded = 0
    var agent_reported_used = 0
    var agent_reported_skipped = 0
    var legacy_resolver_selected = 0
}
struct SkillUsageReason: Content, Sendable {
    let reason: String
    let count: Int
}
struct SkillUsageVersion: Content, Sendable {
    let release_id: String?
    let version: String?
    let checksum: String?
    var counts: SkillUsageCounts
}
struct SkillUsageRow: Content, Sendable {
    let skill_id: String
    let name: String
    let is_current: Bool
    let last_activity: String?
    let counts: SkillUsageCounts
    var versions: [SkillUsageVersion]
    var resolver_exclusion_reasons: [SkillUsageReason]
    var agent_skip_reasons: [SkillUsageReason]
}
struct SkillUsageResponse: Content, Sendable {
    let collection_enabled: Bool
    let retention_days: Int
    let requested_window: String
    let effective_from: String
    let effective_to: String
    let reporting_coverage: String
    let historical_measurements: String
    let page: Int
    let page_size: Int
    let total: Int
    let skills: [SkillUsageRow]
}
