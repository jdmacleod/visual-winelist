import XCTest

// iOS tests that exercise UIKit-dependent code (CameraPreviewView, ContentView, etc.)
// must run on a simulator:
//
//   xcodebuild test -package-path ios \
//     -destination "platform=iOS Simulator,name=iPhone 16"
//
// Simulator-based CI wiring is tracked in T12.
// Pure-logic tests (SSEParser, BackendModels) will be added in T9 once the
// platform-agnostic core is extracted into its own library target.

final class IOSTestSuite: XCTestCase {
    func testTestTargetExists() {
        // Placeholder — verifies the test target infrastructure is in place.
        // Replace with real tests in T9 (SSEParser) and T10 (IOSScanSession).
        XCTAssertTrue(true)
    }
}
