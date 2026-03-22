import Vapor

/// Deployment tier from `APP_ENV`. Invalid or missing values default to **production** (fail closed).
enum DeployAppEnv: String, Sendable {
    case local
    case dev
    case prod
}

enum AppEnvironment {
    /// Unit tests only (`@testable import App`); always nil in production.
    nonisolated(unsafe) static var _testOverrideAppEnv: String?
    /// Unit tests only; when set, overrides `STRICT_PRO_GATING` parsing.
    nonisolated(unsafe) static var _testOverrideStrict: Bool?

    /// Parsed `APP_ENV`: `local`, `dev`, or `prod`. Unknown/empty → `prod`.
    static func deployKind() -> DeployAppEnv {
        let raw = (_testOverrideAppEnv ?? Environment.get("APP_ENV"))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        switch raw {
        case "local": return .local
        case "dev": return .dev
        case "prod", "": return .prod
        default: return .prod
        }
    }

    /// When true, non-production Pro and sync rate-limit bypasses are **disabled** (Stripe + `INTERNAL_PRO_*` still apply).
    static var strictProGating: Bool {
        if let o = _testOverrideStrict { return o }
        guard let s = Environment.get("STRICT_PRO_GATING"), !s.isEmpty else { return false }
        let v = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return v == "1" || v == "true" || v == "yes"
    }

    static var isNonProduction: Bool {
        switch deployKind() {
        case .local, .dev: return true
        case .prod: return false
        }
    }

    /// Pro entitlement + sync rate-limit relaxations apply only in local/dev when not strict.
    static var nonProductionBypassesActive: Bool {
        isNonProduction && !strictProGating
    }

    static var appEnvString: String {
        deployKind().rawValue
    }
}
