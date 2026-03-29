import Fluent
import FluentPostgresDriver
import FluentSQLiteDriver
import NIOSSL
import PostgresKit
import Vapor

private func isTruthyEnv(_ key: String) -> Bool {
    guard let raw = Environment.get(key) else { return false }
    let v = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return v == "1" || v == "true" || v == "yes"
}

public func configure(_ app: Application) throws {
    let deploy = AppEnvironment.deployKind()
    let bypass = AppEnvironment.nonProductionBypassesActive
    let strict = AppEnvironment.strictProGating
    app.logger.info(
        "APP_ENV=\(deploy.rawValue) non_production_bypasses=\(bypass) STRICT_PRO_GATING=\(strict)"
    )

    app.middleware.use(SecurityHeadersMiddleware(), at: .beginning)
    app.middleware.use(BrowserOriginValidationMiddleware(), at: .beginning)

    let corsOrigin = Environment.get("FRONTEND_URL") ?? Environment.get("CORS_ORIGIN") ?? "http://localhost:3000"
    // Echo Sec-Fetch / localhost origins only in local dev; staging/prod must use an explicit allow-list.
    // Non-prod + localhost in config: echo request Origin (localhost vs 127.0.0.1). Prod uses fixed allow-list.
    let allowedOrigin: CORSMiddleware.AllowOriginSetting =
        (AppEnvironment.isNonProduction && corsOrigin.contains("localhost"))
        ? .originBased
        : .custom(corsOrigin)
    let corsConfig = CORSMiddleware.Configuration(
        allowedOrigin: allowedOrigin,
        allowedMethods: [.GET, .POST, .PUT, .OPTIONS, .DELETE, .PATCH],
        allowedHeaders: [.accept, .authorization, .contentType, .origin, .xRequestedWith],
        allowCredentials: true
    )
    app.middleware.use(CORSMiddleware(configuration: corsConfig), at: .beginning)

    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
    app.routes.defaultMaxBodySize = "5mb"

    if AppEnvironment.useMemorySessions {
        app.sessions.use(.memory)
    } else {
        app.sessions.use { _ in FluentSessionDriver() }
    }
    // Allow session cookie over HTTP on localhost (isSecure: false) so OAuth redirect flow works
    let isLocalhost = corsOrigin.contains("localhost")
    // When the browser hits both the app host (e.g. testing.app.com) and the API host (e.g. api.testing.app.com),
    // host-only cookies are not shared. Set SESSION_COOKIE_DOMAIN to the registrable domain (e.g. .mycontextprotocol.dev)
    // so GitHub App Setup URL can use the API host and still receive the same session + install fallback keys.
    let sessionCookieDomain: String? = {
        if isLocalhost { return nil }
        let raw = Environment.get("SESSION_COOKIE_DOMAIN")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? nil : raw
    }()
    if let domain = sessionCookieDomain {
        app.logger.info("Session cookie Domain=\(domain) (shared across subdomains)")
    }
    app.sessions.configuration.cookieFactory = { sessionID in
        .init(
            string: sessionID.string,
            domain: sessionCookieDomain,
            path: "/",
            isSecure: !isLocalhost,
            isHTTPOnly: true,
            sameSite: .lax
        )
    }
    app.middleware.use(app.sessions.middleware)

    /// When `true`, integration tests may use `DATABASE_URL` / `SUPABASE_DB_URL` instead of in-memory SQLite.
    let usePostgresInTests = isTruthyEnv("TEST_USE_POSTGRES")

    if app.environment == .testing, !usePostgresInTests {
        app.databases.use(.sqlite(.memory), as: .sqlite)
    } else if isTruthyEnv("USE_SQLITE") {
        // Local dev: file-backed SQLite (leave DATABASE_URL empty). Path is relative to the process working directory.
        let rawPath = Environment.get("SQLITE_PATH") ?? "db.sqlite"
        let sqlitePath = rawPath.hasPrefix("/") ? rawPath : app.directory.workingDirectory + rawPath
        app.databases.use(.sqlite(.file(sqlitePath)), as: .sqlite)
        app.logger.info("Using SQLite database at \(sqlitePath)")
    } else if let databaseURL = Environment.get("DATABASE_URL"), !databaseURL.isEmpty {
        let useInsecureTLS = Environment.get("DATABASE_INSECURE_TLS").map { $0.lowercased() }.map { $0 == "1" || $0 == "true" } ?? false
        if useInsecureTLS {
            var config = try SQLPostgresConfiguration(url: databaseURL)
            var tlsConfig = TLSConfiguration.makeClientConfiguration()
            tlsConfig.certificateVerification = .none
            config.coreConfiguration.tls = .require(try NIOSSLContext(configuration: tlsConfig))
            app.databases.use(.postgres(configuration: config), as: .psql)
        } else {
            app.databases.use(try .postgres(url: databaseURL), as: .psql)
        }
    } else if let url = Environment.get("SUPABASE_DB_URL"), !url.isEmpty {
        app.databases.use(try .postgres(url: url), as: .psql)
    } else if app.environment == .testing {
        app.databases.use(.sqlite(.memory), as: .sqlite)
    } else {
        let hostname = Environment.get("DATABASE_HOST") ?? "localhost"
        let username = Environment.get("DATABASE_USERNAME") ?? "vapor_username"
        let password = Environment.get("DATABASE_PASSWORD") ?? "vapor_password"
        let database = Environment.get("DATABASE_NAME") ?? "vapor_database"
        let port = Environment.get("DATABASE_PORT").flatMap(Int.init) ?? 5432

        let pgConfig = SQLPostgresConfiguration(
            hostname: hostname,
            port: port,
            username: username,
            password: password,
            database: database,
            tls: .disable
        )
        app.databases.use(.postgres(configuration: pgConfig), as: .psql)
    }

    app.migrations.add(CreateAccounts())
    app.migrations.add(CreateProjects())
    app.migrations.add(CreateRepoConnections())
    app.migrations.add(CreateReleases())
    app.migrations.add(CreateSkillPackages())
    app.migrations.add(CreateToolsIndex())
    app.migrations.add(CreateAuthConfigs())
    app.migrations.add(CreateApiKeys())
    app.migrations.add(CreateRequestLogs())
    app.migrations.add(SeedPersonalUse())
    app.migrations.add(AlterAccountsForOAuth())
    app.migrations.add(AddSaaSFields())
    app.migrations.add(CreateCompiledSkills())
    app.migrations.add(CreateRoutingRules())
    app.migrations.add(CreateCapabilityDefs())
    app.migrations.add(CreateValidationReports())
    app.migrations.add(AddBillingToAccounts())
    app.migrations.add(AlterProjectsTenantAndDomain())
    app.migrations.add(AddGithubInstallationToRepoConnections())
    app.migrations.add(CreateGitHubAppInstallIntents())
    app.migrations.add(AddGithubAppInstallationIdToAccounts())
    app.migrations.add(AddCompiledSkillSkillBody())
    app.migrations.add(AddRequestLogErrorMessage())
    app.migrations.add(AddNameToApiKeys())
    app.migrations.add(AddAgentHintsToRoutingRules())
    app.migrations.add(AddCompiledSkillBodyDiffAndReleaseCounts())
    app.migrations.add(NormalizeRepoDefaultBranchToMain())
    app.migrations.add(CreateAppSessions())
    app.migrations.add(CreateOAuthHandoffTokens())
    app.migrations.add(AddAdminFlagsToAccounts())
    app.migrations.add(CreateAdminAnalyticsHourly())

    try app.autoMigrate().wait()

    app.lifecycle.use(AdminAnalyticsRollupLifecycle())

    try routes(app)
}
