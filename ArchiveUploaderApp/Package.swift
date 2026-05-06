// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ArchiveUploader",
    platforms: [.macOS(.v14)],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "ArchiveUploader",
            path: "Sources",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        )
    ]
)
