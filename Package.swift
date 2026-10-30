// swift-tools-version: 6.0
import PackageDescription

let macOS12Target: [SwiftSetting] = [
    .unsafeFlags(["-target", "arm64-apple-macos12.0"]),
]

let package = Package(
    name: "backup-folder",
    products: [
        .executable(name: "backup-folder", targets: ["backup-folder"]),
        .executable(name: "drop-box-watcher", targets: ["drop-box-watcher"]),
    ],
    targets: [
        .target(
            name: "BuildStamp",
            path: "Sources/BuildStamp",
            swiftSettings: macOS12Target
        ),
        .executableTarget(
            name: "backup-folder",
            dependencies: ["BuildStamp"],
            path: "Sources/backup-folder",
            swiftSettings: macOS12Target + [
                .swiftLanguageMode(.v5),
            ]
        ),
        .executableTarget(
            name: "drop-box-watcher",
            dependencies: ["BuildStamp"],
            path: "drop-box-watcher",
            swiftSettings: macOS12Target + [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
