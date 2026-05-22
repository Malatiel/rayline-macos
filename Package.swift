// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "veil",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "VeilCore",
            path: "App",
            exclude: [
                "ContentView.swift",
                "Info.plist",
                "LogScreen.swift",
                "ProfilesScreen.swift",
                "SettingsScreen.swift",
                "SharedViews.swift",
                "StatusScreen.swift",
                "VeilApp.swift",
                "build.sh"
            ],
            sources: [
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
            name: "VeilTests",
            dependencies: ["VeilCore"],
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
                "VPNManagerTests.swift"
            ],
            resources: [
                .process("shared_test_cases.json")
            ]
        )
    ]
)
