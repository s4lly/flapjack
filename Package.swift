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
        ),
        // Covers the pure, view-independent logic (currently the announcement
        // timetable). It depends on the executable target directly rather than
        // that logic being split into a library, so there is one copy of the
        // rules and no extra module boundary to keep in sync.
        .testTarget(
            name: "FlapjackTests",
            dependencies: ["Flapjack"],
            path: "Tests/FlapjackTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
