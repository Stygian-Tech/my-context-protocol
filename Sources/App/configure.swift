import Fluent
import FluentPostgresDriver
import FluentSQLiteDriver
import Vapor

public func configure(_ app: Application) throws {
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
    app.routes.defaultMaxBodySize = "10mb"

    app.sessions.use(.memory)
    app.middleware.use(app.sessions.middleware)

    if app.environment == .testing {
        try app.databases.use(.sqlite(.memory), as: .sqlite)
    } else if let databaseURL = Environment.get("DATABASE_URL") {
        try app.databases.use(.postgres(url: databaseURL), as: .psql)
    } else if app.environment != .testing, let url = Environment.get("SUPABASE_DB_URL") {
        try app.databases.use(.postgres(url: url), as: .psql)
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

    try app.autoMigrate().wait()

    try routes(app)
}
