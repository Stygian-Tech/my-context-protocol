import Fluent
import FluentPostgresDriver
import FluentSQLiteDriver
import NIOSSL
import PostgresKit
import Vapor

public func configure(_ app: Application) throws {
    let deploy = AppEnvironment.deployKind()
    let bypass = AppEnvironment.nonProductionBypassesActive
    let strict = AppEnvironment.strictProGating
    app.logger.info(
        "APP_ENV=\(deploy.rawValue) non_production_bypasses=\(bypass) STRICT_PRO_GATING=\(strict)"
    )

    let corsOrigin = Environment.get("CORS_ORIGIN") ?? "http://localhost:3000"
    // Use .originBased in dev to echo the request's Origin—avoids mismatch (localhost vs 127.0.0.1)
    // and ensures CORS headers are correct for credentials: include.
    let allowedOrigin: CORSMiddleware.AllowOriginSetting = corsOrigin.contains("localhost")
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
    app.routes.defaultMaxBodySize = "10mb"

    app.sessions.use(.memory)
    // Allow session cookie over HTTP on localhost (isSecure: false) so OAuth redirect flow works
    let isLocalhost = (Environment.get("CORS_ORIGIN") ?? "").contains("localhost")
    app.sessions.configuration.cookieFactory = { sessionID in
        .init(string: sessionID.string, isSecure: !isLocalhost)
    }
    app.middleware.use(app.sessions.middleware)

    if let databaseURL = Environment.get("DATABASE_URL"), !databaseURL.isEmpty {
        let useInsecureTLS = Environment.get("DATABASE_INSECURE_TLS").map { $0.lowercased() }.map { $0 == "1" || $0 == "true" } ?? false
        if useInsecureTLS {
            var config = try SQLPostgresConfiguration(url: databaseURL)
            var tlsConfig = TLSConfiguration.makeClientConfiguration()
            tlsConfig.certificateVerification = .none
            config.coreConfiguration.tls = .require(try NIOSSLContext(configuration: tlsConfig))
            try app.databases.use(.postgres(configuration: config), as: .psql)
        } else {
            try app.databases.use(.postgres(url: databaseURL), as: .psql)
        }
    } else if let url = Environment.get("SUPABASE_DB_URL") {
        try app.databases.use(.postgres(url: url), as: .psql)
    } else if app.environment == .testing {
        try app.databases.use(.sqlite(.memory), as: .sqlite)
    } else {
        let hostname = Environment.get("DATABASE_HOST") ?? "localhost"
        let username = Environment.get("DATABASE_USERNAME") ?? "vapor_username"
        let password = Environment.get("DATABASE_PASSWORD") ?? "vapor_password"
        let database = Environment.get("DATABASE_NAME") ?? "vapor_database"
        let port = Environment.get("DATABASE_PORT").flatMap(Int.init) ?? 5432

        try app.databases.use(
            .postgres(
                hostname: hostname,
                port: port,
                username: username,
                password: password,
                database: database
            ),
            as: .psql
        )
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

    try app.autoMigrate().wait()

    try routes(app)
}
