// iOS tests run via:
//   xcodebuild test -package-path ios \
//     -destination "platform=iOS Simulator,name=iPhone 16"

import XCTest

@testable import VisualWinelistIOS

@MainActor
final class WineListViewModelTests: XCTestCase {

    override func tearDown() async throws {
        await MockProtocolRegistry.shared.reset()
        try await super.tearDown()
    }

    private func makeClient() -> BackendClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return BackendClient(
            baseURL: URL(string: "http://localhost:8000")!,
            session: URLSession(configuration: config)
        )
    }

    private func makeViewModel() -> WineListViewModel {
        WineListViewModel(backend: makeClient())
    }

    // MARK: - checkHealth → backendStatus

    func testCheckHealthSetsStatusOK() async {
        let json = Data(#"{"status":"ok","ollama":true,"brave_key":true}"#.utf8)
        await MockProtocolRegistry.shared.setHandler { _ in
            let url = URL(string: "http://localhost:8000")!
            let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }

        let vm = makeViewModel()
        await vm.checkHealth()

        guard case .ok = vm.backendStatus else {
            XCTFail("Expected backendStatus == .ok, got \(vm.backendStatus)")
            return
        }
    }

    func testCheckHealthURLErrorSetsUnreachable() async {
        await MockProtocolRegistry.shared.setErrorToThrow(URLError(.notConnectedToInternet))

        let vm = makeViewModel()
        await vm.checkHealth()

        guard case .unreachable = vm.backendStatus else {
            XCTFail("Expected backendStatus == .unreachable, got \(vm.backendStatus)")
            return
        }
    }

    func testCheckHealthOllamaFalseSetsDegradedWithOllamaHint() async {
        let json = Data(#"{"status":"ok","ollama":false,"brave_key":true}"#.utf8)
        await MockProtocolRegistry.shared.setHandler { _ in
            let url = URL(string: "http://localhost:8000")!
            let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }

        let vm = makeViewModel()
        await vm.checkHealth()

        guard case .degraded(let message) = vm.backendStatus else {
            XCTFail("Expected backendStatus == .degraded, got \(vm.backendStatus)")
            return
        }
        XCTAssertTrue(
            message.contains("ollama serve"),
            "Degraded message must mention 'ollama serve'; got: \(message)")
    }

    // MARK: - classifyScanError

    func testClassifyScanErrorCancellationHasNoMessage() {
        let result = WineListViewModel.classifyScanError(CancellationError())
        XCTAssertNil(result.message, "user cancellation must not surface an error")
        XCTAssertEqual(result.outcome, "cancelled")
    }

    func testClassifyScanErrorURLCancelledHasNoMessage() {
        let result = WineListViewModel.classifyScanError(URLError(.cancelled))
        XCTAssertNil(result.message, "URLSession cancel must not surface an error")
        XCTAssertEqual(result.outcome, "cancelled")
    }

    func testClassifyScanErrorBackendCasesMapToError() {
        for err in [BackendError.scannerBusy, .invalidImage, .unreachable("http://x")] {
            let result = WineListViewModel.classifyScanError(err)
            XCTAssertNotNil(result.message, "\(err) must surface a message")
            XCTAssertEqual(result.outcome, "error")
        }
    }

    func testClassifyScanErrorGenericFailureSurfacesMessage() {
        let result = WineListViewModel.classifyScanError(URLError(.timedOut))
        XCTAssertEqual(result.outcome, "error")
        XCTAssertTrue(result.message?.contains("Scan failed") ?? false)
    }
}
