import Foundation

enum TenantSubdomainGenerator {
    private static let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")

    /// 12-char lowercase alphanumeric subdomain; cryptographically random.
    static func make() -> String {
        var rng = SystemRandomNumberGenerator()
        return String((0 ..< 12).map { _ in alphabet.randomElement(using: &rng)! })
    }
}
