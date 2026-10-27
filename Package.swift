// swift-tools-version: 6.2
import PackageDescription

let swift6: [SwiftSetting] = [.swiftLanguageMode(.v6)]

// The platform-neutral heart: the data model and the `openusage.limits.v1` contract. Foundation only
// (CoreImportsTests enforces it), so it builds on every platform Swift runs on, Windows included.
var products: [Product] = [
    .library(name: "OpenUsageCore", targets: ["OpenUsageCore"])
]
var dependencies: [Package.Dependency] = []
var targets: [Target] = [
    .target(name: "OpenUsageCore", path: "Sources/OpenUsageCore", swiftSettings: swift6),
    .testTarget(
        name: "OpenUsageCoreTests",
        dependencies: ["OpenUsageCore"],
        path: "Tests/OpenUsageCoreTests",
        swiftSettings: swift6
    )
]

// The menu-bar app and everything built on AppKit, SwiftUI, and the Keychain exist only on macOS.
#if os(macOS)
products += [
    .executable(name: "OpenUsage", targets: ["OpenUsageApp"]),
    // Named apart from `openusage` (the command users run): macOS paths ignore case, so the two
    // would collide. The app's installer links `openusage` to this binary.
    .executable(name: "openusage-cli", targets: ["OpenUsageCLI"])
]
dependencies += [
    .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.0.1")
]
targets += [
    .target(
        name: "OpenUsage",
        dependencies: [
            "OpenUsageCore",
            .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
        ],
        path: "Sources/OpenUsage",
        resources: [
            .copy("Resources/ProviderIcons")
        ],
        swiftSettings: swift6
    ),
    .executableTarget(name: "OpenUsageApp", dependencies: ["OpenUsage"], path: "Sources/OpenUsageApp", swiftSettings: swift6),
    .executableTarget(name: "OpenUsageCLI", dependencies: ["OpenUsage"], path: "Sources/OpenUsageCLI", swiftSettings: swift6),
    .testTarget(
        name: "OpenUsageTests",
        dependencies: ["OpenUsage", "OpenUsageCore"],
        path: "Tests/OpenUsageTests",
        swiftSettings: swift6
    )
]
#endif

// The Windows command line: the same core, with Windows' own encrypted credential store and data folder.
#if os(Windows)
products += [
    .executable(name: "openusage", targets: ["OpenUsageWindowsCLI"]),
    .executable(name: "OpenUsageLight", targets: ["OpenUsageWindowsApp"])
]
targets += [
    .target(
        name: "OpenUsageWindows",
        dependencies: ["OpenUsageCore"],
        path: "Sources/OpenUsageWindows",
        swiftSettings: swift6,
        linkerSettings: [.linkedLibrary("Crypt32"), .linkedLibrary("Dwmapi"), .linkedLibrary("Shell32"), .linkedLibrary("Ws2_32")]
    ),
    // The tray app: a GUI-subsystem program, so no console window opens beside it.
    .executableTarget(
        name: "OpenUsageWindowsApp",
        dependencies: ["OpenUsageWindows"],
        path: "Sources/OpenUsageWindowsApp",
        swiftSettings: swift6,
        linkerSettings: [.unsafeFlags(["-Xlinker", "/SUBSYSTEM:WINDOWS", "-Xlinker", "/ENTRY:mainCRTStartup"])]
    ),
    .executableTarget(name: "OpenUsageWindowsCLI", dependencies: ["OpenUsageWindows"], path: "Sources/OpenUsageWindowsCLI", swiftSettings: swift6),
    .testTarget(
        name: "OpenUsageWindowsTests",
        dependencies: ["OpenUsageCore", "OpenUsageWindows"],
        path: "Tests/OpenUsageWindowsTests",
        swiftSettings: swift6
    )
]
#endif

let package = Package(
    name: "OpenUsage",
    platforms: [
        .macOS(.v15)
    ],
    products: products,
    dependencies: dependencies,
    targets: targets
)
