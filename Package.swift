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
            sources: [
                "LocalizationTests.swift",
                "TCPProbeTests.swift",
                "ProxyParserTests.swift",
                "ProfileImportParserTests.swift",
                "ProfileManagerTests.swift",
                "SubscriptionManagerTests.swift",
                "ProfilesSummaryTests.swift",
                "SharedCasesTests.swift",
                "SettingsSummaryTests.swift",
                "StatusSummaryTests.swift",
                "LifecycleRecoveryTests.swift",
                "DiagnosticExporterTests.swift",
                "AppPathsTests.swift",
                "VPNManagerTests.swift"
            ],
            resources: [
                .process("shared_test_cases.json")
            ]
        )
    ]
)
