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
                .copy("Resources/Settings.bundle")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        // UIKit-dependent code prevents linking VisualWinelistIOS on macOS.
        // Real tests run via: xcodebuild test -package-path ios
        //   -destination "platform=iOS Simulator,name=iPhone 16"
        // CI wiring comes in a follow-up (T12).
        .testTarget(
            name: "VisualWinelistIOSTests",
            dependencies: ["VisualWinelistIOS"],
            path: "Tests/VisualWinelistIOSTests"
        ),
    ]
)
