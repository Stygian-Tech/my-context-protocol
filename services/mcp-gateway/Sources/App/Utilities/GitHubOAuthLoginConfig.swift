import Vapor

/// Resolves the GitHub **browser login** OAuth callback (`/auth/github/callback`).
/// Do not confuse with `GITHUB_APP_SETUP_CALLBACK_URL` (`/auth/github/app/callback`).
enum GitHubOAuthLoginConfig {
    static let callbackPath = "/auth/github/callback"

    /// Callback URL sent to GitHub for authorize + token exchange.
    static func redirectURI(logger: Logger? = nil) throws -> String {
        let fromWebhook = deriveFromWebhookBase()
        if let explicit = normalizedEnv("GITHUB_OAUTH_REDIRECT_URI") {
            if isMisconfiguredAppCallback(explicit) {
                logger?.error(
                    """
                    GITHUB_OAUTH_REDIRECT_URI points at the GitHub App install callback; \
                    browser login requires \(callbackPath). \
                    Set WEBHOOK_BASE_URL or fix GITHUB_OAUTH_REDIRECT_URI. \
                    Use GITHUB_APP_SETUP_CALLBACK_URL for App install only.
                    """
                )
                guard let derived = fromWebhook else {
                    throw Abort(
                        .internalServerError,
                        reason: "GITHUB_OAUTH_REDIRECT_URI is misconfigured and WEBHOOK_BASE_URL is not set"
                    )
                }
                return preferHttps(derived, logger: logger)
            }
            if explicit.lowercased().hasSuffix(callbackPath) {
                return preferHttps(explicit, logger: logger)
            }
        }
        if let derived = fromWebhook {
            return derived
        }
        if let explicit = normalizedEnv("GITHUB_OAUTH_REDIRECT_URI") {
            return preferHttps(explicit, logger: logger)
        }
        throw Abort(
            .internalServerError,
            reason: "Set WEBHOOK_BASE_URL or GITHUB_OAUTH_REDIRECT_URI for GitHub login OAuth"
        )
    }

    private static func deriveFromWebhookBase() -> String? {
        guard let raw = normalizedEnv("WEBHOOK_BASE_URL") else { return nil }
        return raw.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + callbackPath
    }

    private static func isMisconfiguredAppCallback(_ uri: String) -> Bool {
        uri.lowercased().contains("/auth/github/app/")
    }

    /// GitHub OAuth apps on hosted domains require https; Fly/proxies often expose http in legacy env vars.
    private static func preferHttps(_ uri: String, logger: Logger?) -> String {
        let lower = uri.lowercased()
        guard lower.hasPrefix("http://"),
              !lower.contains("localhost"),
              !lower.contains("127.0.0.1") else {
            return uri
        }
        let upgraded = "https://" + String(uri.dropFirst("http://".count))
        logger?.warning("GitHub login redirect_uri upgraded to HTTPS: \(upgraded)")
        return upgraded
    }

    private static func normalizedEnv(_ key: String) -> String? {
        guard let raw = Environment.get(key) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
