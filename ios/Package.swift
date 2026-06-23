// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VisualWinelistIOS",
    platforms: [.iOS(.v17), .macOS(.v13)],
    targets: [
        // DebugBridgeCore — StateServer + bridge protocols. Foundation+Network only,
        // cross-platform. Compiled in both Debug and Release; code inside is
        // #if DEBUG gated so Release links near-zero bytes.
        .target(
            name: "DebugBridgeCore",
            dependencies: [],
            path: "Sources/DebugBridgeCore",
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        // DebugBridgeTouch — KIF-derived in-process touch synthesis (ObjC, iOS-only).
        .target(
            name: "DebugBridgeTouch",
            dependencies: [],
            path: "Sources/DebugBridgeTouch",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("UIKit", .when(platforms: [.iOS]))
            ]
        ),
        // DebugBridgeUI — UIKit bridge implementations (screenshot, elements, mutation).
        .target(
            name: "DebugBridgeUI",
            dependencies: ["DebugBridgeCore", "DebugBridgeTouch"],
            path: "Sources/DebugBridgeUI",
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .executableTarget(
            name: "VisualWinelistIOS",
            dependencies: [
                "DebugBridgeCore",
                "DebugBridgeUI",
            ],
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
