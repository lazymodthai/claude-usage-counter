// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeUsageCounter",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClaudeUsageCounter",
            path: "Sources"
        )
    ]
)
