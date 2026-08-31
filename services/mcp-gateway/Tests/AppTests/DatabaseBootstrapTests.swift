import Foundation
import NIOSSL
import Testing
@testable import App

/// Serialized: mutates process environment for `Environment.get` reads.
@Suite("Database bootstrap — discrete Postgres", .serialized)
struct DatabaseBootstrapTests {
    @Test("dev and prod require host, username, password, and database (port is optional)")
    func remoteRequiresAllDiscrete() throws {
        TestProcessEnvGate.runSync {
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
        TestProcessEnvGate.runSync {
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

    @Test("production rejects disabled Postgres certificate verification")
    func prodRejectsInsecurePostgresTLS() throws {
        #expect(throws: DatabaseBootstrapError.insecurePostgresTLSInProduction) {
            try DatabaseBootstrap.assertInsecurePostgresTLSAllowed(true, deployKind: .prod)
        }

        try DatabaseBootstrap.assertInsecurePostgresTLSAllowed(false, deployKind: .prod)
        try DatabaseBootstrap.assertInsecurePostgresTLSAllowed(true, deployKind: .dev)
        try DatabaseBootstrap.assertInsecurePostgresTLSAllowed(true, deployKind: .local)
    }

    @Test("verified Postgres TLS accepts PEM CA from env")
    func verifiedPostgresTLSAcceptsPEMCAFromEnv() throws {
        try TestProcessEnvGate.runSync {
        let escapedPEM = postgresTestCertificatePEM.replacingOccurrences(of: "\n", with: "\\n")
        let (apply, restore) = temporaryEnv([
            "DATABASE_SSLROOTCERT": nil,
            "DATABASE_SSLROOTCERT_PEM": escapedPEM,
            "DATABASE_SSLROOTCERT_BASE64": nil,
        ])
        apply()
        defer { restore() }

        let roots = try DatabaseBootstrap.postgresAdditionalTrustRoots()
        #expect(roots.count == 1)
        _ = try DatabaseBootstrap.verifiedPostgresSSLContext()
        }
    }

    @Test("verified Postgres TLS accepts base64 PEM CA from env")
    func verifiedPostgresTLSAcceptsBase64PEMCAFromEnv() throws {
        try TestProcessEnvGate.runSync {
        let encodedPEM = Data(postgresTestCertificatePEM.utf8).base64EncodedString()
        let (apply, restore) = temporaryEnv([
            "DATABASE_SSLROOTCERT": nil,
            "DATABASE_SSLROOTCERT_PEM": nil,
            "DATABASE_SSLROOTCERT_BASE64": encodedPEM,
        ])
        apply()
        defer { restore() }

        let roots = try DatabaseBootstrap.postgresAdditionalTrustRoots()
        #expect(roots.count == 1)
        _ = try DatabaseBootstrap.verifiedPostgresSSLContext()
        }
    }

    @Test("verified Postgres TLS accepts sslrootcert from URL")
    func verifiedPostgresTLSAcceptsSSLRootCertURLParameter() throws {
        try TestProcessEnvGate.runSync {
        let (apply, restore) = temporaryEnv([
            "DATABASE_SSLROOTCERT": nil,
            "DATABASE_SSLROOTCERT_PEM": nil,
            "DATABASE_SSLROOTCERT_BASE64": nil,
        ])
        apply()
        defer { restore() }

        let roots = try DatabaseBootstrap.postgresAdditionalTrustRoots(
            connectionURL: "postgres://user:pass@db.example.com:5432/postgres?sslmode=require&sslrootcert=/etc/ssl/certs/supabase-ca.pem"
        )
        #expect(roots.count == 1)
        if case .file(let path) = roots[0] {
            #expect(path == "/etc/ssl/certs/supabase-ca.pem")
        } else {
            Issue.record("Expected sslrootcert to load as a file trust root")
        }
        }
    }

    @Test("verified Postgres TLS rejects invalid base64 CA env")
    func verifiedPostgresTLSRejectsInvalidBase64CAFromEnv() throws {
        TestProcessEnvGate.runSync {
        let (apply, restore) = temporaryEnv([
            "DATABASE_SSLROOTCERT": nil,
            "DATABASE_SSLROOTCERT_PEM": nil,
            "DATABASE_SSLROOTCERT_BASE64": "not base64",
        ])
        apply()
        defer { restore() }

        #expect(throws: DatabaseBootstrapError.invalidPostgresTLSRoot(reason: "DATABASE_SSLROOTCERT_BASE64 is not valid base64")) {
            try DatabaseBootstrap.postgresAdditionalTrustRoots()
        }
        }
    }

    @Test("production rejects loopback Postgres URL hosts")
    func prodRejectsLoopbackPostgresURLHosts() throws {
        try TestProcessEnvGate.runSync {
        let previous = AppEnvironment._testOverrideAppEnv
        AppEnvironment._testOverrideAppEnv = "prod"
        defer { AppEnvironment._testOverrideAppEnv = previous }

        #expect(throws: DatabaseBootstrapError.loopbackPostgresHostInDeployedAppEnv(host: "127.0.0.1")) {
            try DatabaseBootstrap.assertPostgresConnectionURLHostAllowedIfResolvable("postgres://u:p@127.0.0.1:5432/db")
        }
        try DatabaseBootstrap.assertPostgresConnectionURLHostAllowedIfResolvable("postgres://u:p@db.example.com:5432/db")
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

private let postgresTestCertificatePEM = """
-----BEGIN CERTIFICATE-----
MIIDEzCCAfugAwIBAgIURiMaUmhI1Xr0mZ4p+JmI0XjZTaIwDQYJKoZIhvcNAQEL
BQAwFDESMBAGA1UEAwwJbG9jYWxob3N0MB4XDTE3MTAzMDEyMDUwMFoXDTQwMDEw
MTAwMDAwMFowFDESMBAGA1UEAwwJbG9jYWxob3N0MIIBIjANBgkqhkiG9w0BAQEF
AAOCAQ8AMIIBCgKCAQEA26DcKAxqdWivhS/J3Klf+cEnrT2cDzLhmVRCHuQZXiIr
tqr5401KDbRTVOg8v2qIyd8x4+YbpE47JP3fBrcMey70UK/Er8nu28RY3z7gZLLi
Yf+obHdDFCK5JaCGmM61I0c0vp7aMXsyv7h3vjEzTuBMlKR8p37ftaXSUAe3Qk/D
/fzA3k02E2e3ap0Sapd/wUu/0n/MFyy9HkkeykivAzLaaFhhvp3hATdFYC4FLld8
OMB60bC2S13CAljpMlpjU/XLLOUbaPgnNUqE1nFqFBoTl6kV6+ii8Dd5ENVvE7pE
SoNoyGLDUkDRJJMNUHAo0zbxyhd7WOtyZ7B4YBbPswIDAQABo10wWzBLBgNVHREE
RDBCgglsb2NhbGhvc3SCC2V4YW1wbGUuY29tgRB1c2VyQGV4YW1wbGUuY29thwTA
qAABhxAgAQ24AAAAAAAAAAAAAAABMAwGA1UdEwEB/wQCMAAwDQYJKoZIhvcNAQEL
BQADggEBACYBArIoL9ZzVX3M+WmTD5epmGEffrH7diRJZsfpVXi86brBPrbvpTBx
Fa+ZKxBAchPnWn4rxoWVJmTm4WYqZljek7oQKzidu88rMTbsxHA+/qyVPVlQ898I
hgnW4h3FFapKOFqq5Hj2gKKItFIcGoVY2oLTBFkyfAx0ofromGQp3fh58KlPhC0W
GX1nFCea74mGyq60X86aEWiyecYYj5AEcaDrTnGg3HLGTsD3mh8SUZPAda13rO4+
RGtGsA1C9Yovlu9a6pWLgephYJ73XYPmRIGgM64fkUbSuvXNJMYbWnzpoCdW6hka
IEaDUul/WnIkn/JZx8n+wgoWtyQa4EA=
-----END CERTIFICATE-----
"""
