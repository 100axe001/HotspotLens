// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HotspotLens",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "HotspotLensCore", targets: ["HotspotLensCore"]),
        .executable(name: "hotspotlens-cli", targets: ["HotspotLensCLI"])
    ],
    dependencies: [
        // GRDB + SQLCipher provide genuine at-rest encryption for the local
        // history database (see README "Tech Stack" for the SwiftData vs
        // GRDB decision). Both are local, source-available libraries with
        // no network/telemetry behavior.
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0")
    ],
    targets: [
        .target(
            name: "HotspotLensCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/HotspotLensCore",
            resources: [
                .copy("Resources/oui_vendors.json")
            ]
        ),
        .executableTarget(
            name: "HotspotLensCLI",
            dependencies: ["HotspotLensCore"],
            path: "Sources/HotspotLensCLI"
        ),
        .testTarget(
            name: "HotspotLensCoreTests",
            dependencies: ["HotspotLensCore"],
            path: "Tests/HotspotLensCoreTests",
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
