// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "unreel",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "unreel-engine",
            targets: ["unreel-engine"]
        ),
        .executable(
            name: "unreel",
            targets: ["unreel"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        // Core library with podcast feed parsing, database, and download functionality
        .target(
            name: "unreel-engine",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        // CLI executable
        .executableTarget(
            name: "unreel",
            dependencies: [
                "unreel-engine",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        // Tests for unreel-engine
        .testTarget(
            name: "unreel-engineTests",
            dependencies: ["unreel-engine"]
        )
    ]
)
