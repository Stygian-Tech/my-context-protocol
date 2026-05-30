// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MyContextProtocol",
    platforms: [
        .macOS(.v13),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.89.0"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.8.0"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.7.0"),
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.2.0"),
        .package(url: "https://github.com/vapor/sql-kit.git", from: "3.32.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        .package(url: "https://github.com/vapor/jwt-kit.git", from: "4.13.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(path: "../../../../mcp-server-kit"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
                .product(name: "SQLKit", package: "sql-kit"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "JWTKit", package: "jwt-kit"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "MCPServerKit", package: "mcp-server-kit"),
            ],
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "AppTests",
            dependencies: [
                .target(name: "App"),
                .product(name: "VaporTesting", package: "vapor"),
                .product(name: "Crypto", package: "swift-crypto"),
            ],
            path: "Tests/AppTests",
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
    ]
)
