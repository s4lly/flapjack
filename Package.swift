// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Flapjack",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Flapjack",
            path: "Sources/Flapjack",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
