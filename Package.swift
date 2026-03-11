// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "veil",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "VeilCore",
            path: "App",
            sources: ["ProxyParser.swift"]
        ),
        .testTarget(
            name: "VeilTests",
            dependencies: ["VeilCore"],
            path: "Tests",
            sources: ["ProxyParserTests.swift"]
        )
    ]
)
