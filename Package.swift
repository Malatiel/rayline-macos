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
                "VeilApp.swift",
                "build.sh"
            ],
            sources: [
                "ProxyParser.swift",
                "ProfileManager.swift",
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
            exclude: [
                "test_config.cpp",
                "test_proxy_parser.cpp",
                "test_shared_cases.cpp",
                "test_wireguard.cpp"
            ],
            sources: [
                "ProxyParserTests.swift",
                "ProfileManagerTests.swift",
                "SharedCasesTests.swift",
                "VPNManagerTests.swift"
            ],
            resources: [
                .process("shared_test_cases.json")
            ]
        )
    ]
)
