// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VisualWinelistIOS",
    platforms: [.iOS(.v16)],
    targets: [
        .executableTarget(
            name: "VisualWinelistIOS",
            path: "Sources/VisualWinelistIOS",
            resources: [
                .copy("Resources/Settings.bundle"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        )
    ]
)
