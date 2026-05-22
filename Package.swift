// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "rayline",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "RaylineCore",
            path: "App",
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
            ],
            sources: [
                "AppPaths.swift",
                "ProxyParser.swift",
                "ProfileImportParser.swift",
                "ProfileManager.swift",
                "SubscriptionManager.swift",
                "ProfilesSummary.swift",
                "SettingsSummary.swift",
                "StatusSummary.swift",
                "LifecycleRecovery.swift",
                "DiagnosticExporter.swift",
                "LanguageManager.swift",
                "VPNManager.swift",
                "ToastManager.swift",
                "ThemeManager.swift"
            ]
        ),
        .testTarget(
            name: "RaylineTests",
            dependencies: ["RaylineCore"],
            path: "Tests",
            sources: [
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
