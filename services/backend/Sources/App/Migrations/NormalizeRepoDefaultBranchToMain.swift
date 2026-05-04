import Fluent

/// Reserved migration slot (no-op). Webhook sync uses GitHub’s `repository.default_branch` (HEAD)
/// instead of rewriting stored branch names here.
struct NormalizeRepoDefaultBranchToMain: AsyncMigration {
    func prepare(on database: Database) async throws {}

    func revert(on database: Database) async throws {}
}
