// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacWhisperer",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
    ],
    targets: [
        .systemLibrary(
            name: "CWhisper",
            path: "Vendor/CWhisper",
            pkgConfig: nil,
            providers: []
        ),
        .systemLibrary(
            name: "CSherpaOnnx",
            path: "Vendor/CSherpaOnnx",
            pkgConfig: nil,
            providers: []
        ),
        .executableTarget(
            name: "MacWhisperer",
            dependencies: [
                "CWhisper",
                "CSherpaOnnx",
                "KeyboardShortcuts",
            ],
            path: "Sources",
            exclude: ["Info.plist"],
            resources: [
                .process("../Resources"),
            ],
            cSettings: [
                .headerSearchPath("../Vendor/whisper-built/include"),
                .headerSearchPath("../Vendor/sherpa-onnx-built/include"),
            ],
            swiftSettings: [
                .unsafeFlags([
                    "-I", "Vendor/whisper-built/include",
                    "-I", "Vendor/sherpa-onnx-built/include",
                ]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L", "Vendor/whisper-built/lib",
                    "-L", "Vendor/sherpa-onnx-built/lib",
                ]),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Foundation"),
                .linkedLibrary("c++"),
            ]
        ),
    ]
)
