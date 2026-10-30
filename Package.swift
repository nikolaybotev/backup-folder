// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "backup-folder",
    products: [
        .executable(name: "backup-folder", targets: ["backup-folder"]),
        .executable(name: "drop-box-watcher", targets: ["drop-box-watcher"]),
    ],
    targets: [
        .target(
            name: "BuildStamp",
            path: "Sources/BuildStamp"
        ),
        .executableTarget(
            name: "backup-folder",
            dependencies: ["BuildStamp"],
            path: "Sources/backup-folder",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .executableTarget(
            name: "drop-box-watcher",
            dependencies: ["BuildStamp"],
            path: "drop-box-watcher",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
