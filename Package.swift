// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeUsageMiniBar",
    platforms: [
        // MenuBarExtra requires macOS 13 (Ventura) or later.
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ClaudeUsageMiniBar", targets: ["ClaudeUsageMiniBar"])
    ],
    targets: [
        .executableTarget(
            name: "ClaudeUsageMiniBar",
            path: "Sources/ClaudeUsageMiniBar",
            // Keep language mode at v5 so the skeleton compiles cleanly everywhere while
            // still being written to satisfy Swift 6 strict concurrency where it matters.
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            // The app reads the OAuth token from the macOS Keychain (Security.framework)
            // and renders a SwiftUI menu bar UI (AppKit + SwiftUI). Both ship with the SDK.
            linkerSettings: [
                .linkedFramework("Security"),
                .linkedFramework("AppKit")
            ]
        )
    ]
)
