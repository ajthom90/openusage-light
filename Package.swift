// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OpenUsage",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "OpenUsage", targets: ["OpenUsageApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.0.1")
    ],
    targets: [
        .target(
            name: "OpenUsage",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ],
            path: "Sources/OpenUsage",
            resources: [
                .copy("Resources/ProviderIcons")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "OpenUsageApp",
            dependencies: ["OpenUsage"],
            path: "Sources/OpenUsageApp",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "OpenUsageTests",
            dependencies: ["OpenUsage"],
            path: "Tests/OpenUsageTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
