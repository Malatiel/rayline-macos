// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "rayline",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "RaylineCore",
            path: "App",
            // Exclude-only: every App/*.swift is part of the testable core EXCEPT
            // the SwiftUI layer listed here (which needs SwiftUI/AppKit and is not
            // unit-tested). New core files are picked up automatically; only a new
            // UI file needs to be added below. This is the single source of truth
            // for the core/UI split — build.sh compiles the whole App/ directory.
            exclude: [
                "AppIcon.icns",
                "AppIcon.png",
                "ContentView.swift",
                "Info.plist",
                "LogScreen.swift",
                "ProfilesScreen.swift",
                "SettingsScreen.swift",
                "SharedViews.swift",
                "StatusScreen.swift",
                "RaylineApp.swift",
                "build.sh"
            ]
        ),
        .testTarget(
            name: "RaylineTests",
            dependencies: ["RaylineCore"],
            path: "Tests",
            // Auto-discovers every Tests/*.swift; new test files need no entry here.
            resources: [
                .process("shared_test_cases.json")
            ]
        )
    ]
)
