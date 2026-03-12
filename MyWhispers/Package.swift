// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MyWhispers",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.9.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "MyWhispers",
            dependencies: [
                "WhisperKit",
                "KeyboardShortcuts",
            ],
            path: "Sources",
            resources: [
                .process("../Resources"),
            ]
        ),
    ]
)
