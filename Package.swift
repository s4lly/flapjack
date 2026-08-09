// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "FlipClock",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "FlipClock",
            path: "Sources/FlipClock",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
