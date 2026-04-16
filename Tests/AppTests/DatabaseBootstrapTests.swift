import Foundation
import Testing
@testable import App

/// Serialized: mutates process environment for `Environment.get` reads.
@Suite("Database bootstrap — discrete Postgres", .serialized)
struct DatabaseBootstrapTests {
    @Test("dev and prod require host, username, password, and database (port is optional)")
    func remoteRequiresAllDiscrete() throws {
        try TestProcessEnvGate.runSync {
        let requiredKeys = ["DATABASE_HOST", "DATABASE_USERNAME", "DATABASE_PASSWORD", "DATABASE_NAME"]
        for missingKey in requiredKeys {
            var overrides: [String: String?] = [:]
            for k in requiredKeys where k != missingKey {
                overrides[k] = "set"
            }
            overrides[missingKey] = ""
            overrides["DATABASE_PORT"] = "5432"
            let (apply, restore) = temporaryEnv(overrides)
            apply()
            defer { restore() }

            for kind in [DeployAppEnv.dev, DeployAppEnv.prod] {
                #expect(throws: DatabaseBootstrapError.missingRemotePostgresConfiguration) {
                    try DatabaseBootstrap.postgresDiscreteParameters(for: kind)
                }
            }
        }
        }
    }

    @Test("dev and prod accept fully specified discrete fields")
    func remoteHappyPath() throws {
        try TestProcessEnvGate.runSync {
        let (apply, restore) = temporaryEnv([
            "DATABASE_HOST": "db.example.test",
            "DATABASE_USERNAME": "appuser",
            "DATABASE_PASSWORD": "secret",
            "DATABASE_NAME": "appdb",
            "DATABASE_PORT": "5433",
        ])
        apply()
        defer { restore() }

        let expected = PostgresDiscreteConnectionParams(
            hostname: "db.example.test",
            username: "appuser",
            password: "secret",
            database: "appdb",
            port: 5433
        )
        for kind in [DeployAppEnv.dev, DeployAppEnv.prod] {
            let p = try DatabaseBootstrap.postgresDiscreteParameters(for: kind)
            #expect(p == expected)
        }
        }
    }

    @Test("dev and prod default DATABASE_PORT to 5432 when unset")
    func remoteDefaultPort() throws {
        try TestProcessEnvGate.runSync {
        let (apply, restore) = temporaryEnv([
            "DATABASE_HOST": "h",
            "DATABASE_USERNAME": "u",
            "DATABASE_PASSWORD": "p",
            "DATABASE_NAME": "d",
            "DATABASE_PORT": nil,
        ])
        apply()
        defer { restore() }

        let p = try DatabaseBootstrap.postgresDiscreteParameters(for: .prod)
        #expect(p.port == 5432)
        }
    }

    @Test("local uses localhost and vapor_* defaults when discrete vars are unset")
    func localDefaults() throws {
        try TestProcessEnvGate.runSync {
        let (apply, restore) = temporaryEnv([
            "DATABASE_HOST": nil,
            "DATABASE_USERNAME": nil,
            "DATABASE_PASSWORD": nil,
            "DATABASE_NAME": nil,
            "DATABASE_PORT": nil,
        ])
        apply()
        defer { restore() }

        let p = try DatabaseBootstrap.postgresDiscreteParameters(for: .local)
        #expect(p.hostname == "localhost")
        #expect(p.username == "vapor_username")
        #expect(p.password == "vapor_password")
        #expect(p.database == "vapor_database")
        #expect(p.port == 5432)
        }
    }

    @Test("whitespace-only discrete values count as missing in dev/prod")
    func trimmedWhitespaceFails() throws {
        try TestProcessEnvGate.runSync {
        let (apply, restore) = temporaryEnv([
            "DATABASE_HOST": " \t",
            "DATABASE_USERNAME": "u",
            "DATABASE_PASSWORD": "p",
            "DATABASE_NAME": "d",
        ])
        apply()
        defer { restore() }
        #expect(throws: DatabaseBootstrapError.missingRemotePostgresConfiguration) {
            try DatabaseBootstrap.postgresDiscreteParameters(for: .prod)
        }
        }
    }

    @Test("discrete helper does not read DATABASE_URL (configure must prefer URL first)")
    func discreteHelperIgnoresDatabaseUrl() throws {
        try TestProcessEnvGate.runSync {
        let (apply, restore) = temporaryEnv([
            "DATABASE_URL": "postgres://x:y@example.com:5432/db",
            "DATABASE_HOST": "explicit.host",
            "DATABASE_USERNAME": "u",
            "DATABASE_PASSWORD": "p",
            "DATABASE_NAME": "d",
        ])
        apply()
        defer { restore() }
        let p = try DatabaseBootstrap.postgresDiscreteParameters(for: .prod)
        #expect(p.hostname == "explicit.host")
        }
    }
}

private func temporaryEnv(_ overrides: [String: String?]) -> (() -> Void, () -> Void) {
    var saved: [String: String?] = [:]
    for (key, _) in overrides {
        saved[key] = ProcessInfo.processInfo.environment[key]
    }
    let apply: () -> Void = {
        for (key, val) in overrides {
            if let v = val {
                setenv(key, v, 1)
            } else {
                setenv(key, "", 1)
            }
        }
    }
    let restore: () -> Void = {
        for (key, val) in saved {
            if let v = val {
                setenv(key, v, 1)
            } else {
                unsetenv(key)
            }
        }
    }
    return (apply, restore)
}
