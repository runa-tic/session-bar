// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SessionBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SessionBar",
            path: "Sources/SessionBar",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
