// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VisualWinelist",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "VisualWinelist",
            path: "Sources/VisualWinelist",
            exclude: ["Resources/Info.plist"],
            resources: [],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "VisualWinelistTests",
            dependencies: ["VisualWinelist"],
            path: "Tests/VisualWinelistTests"
        )
    ]
)
