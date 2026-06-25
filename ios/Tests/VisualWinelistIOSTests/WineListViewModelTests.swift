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

    func testCheckHealthBraveKeyFalseSetsDegradedWithBraveHint() async {
        let json = Data(#"{"status":"ok","ollama":true,"brave_key":false}"#.utf8)
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
            message.contains("BRAVE_API_KEY"),
            "Degraded message must mention BRAVE_API_KEY; got: \(message)")
    }

    // MARK: - Scan event loop (performScan via SSE)

    /// Frame (event, json) pairs into an SSE body the backend would emit.
    private func sse(_ events: [(String, String)]) -> String {
        events.map { "event: \($0.0)\ndata: \($0.1)\n\n" }.joined()
    }

    /// Run a full scan, serving `body` as the /scan response. When `imageBytes` is
    /// set, GET /wines/{id}/image returns it so the ready-image path can be driven.
    private func runScan(_ body: String, on vm: WineListViewModel, imageBytes: Data? = nil) async {
        await MockProtocolRegistry.shared.setHandler { request in
            let url = request.url!
            let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if url.path.contains("/image"), let imageBytes {
                return (response, imageBytes)
            }
            return (response, Data(body.utf8))
        }
        await vm.scan(photoData: Data([0xFF, 0xD8, 0xFF, 0xD9]))
    }

    func testScanPopulatesGridAndCompletes() async {
        let body = sse([
            ("wine", #"{"name":"Opus One","confidence":0.9,"wine_id":"w1"}"#),
            ("wine", #"{"name":"Margaux","confidence":0.95,"wine_id":"w2"}"#),
            ("complete", #"{"wine_count":2,"cache_hits":0,"scan_id":"s1"}"#),
        ])
        let vm = makeViewModel()
        await runScan(body, on: vm)

        XCTAssertEqual(vm.wines.map(\.wine.name), ["Opus One", "Margaux"])
        XCTAssertFalse(vm.isScanning, "complete event must end scanning")
        XCTAssertEqual(vm.scanProgress, 1.0, accuracy: 0.001)
        XCTAssertNil(vm.errorMessage)
    }

    func testScanDeduplicatesWinesBySameId() async {
        let dup = #"{"name":"Opus One","confidence":0.9,"wine_id":"w1"}"#
        let body = sse([
            ("wine", dup),
            ("wine", dup),
            ("complete", #"{"wine_count":1,"cache_hits":0,"scan_id":"s1"}"#),
        ])
        let vm = makeViewModel()
        await runScan(body, on: vm)

        XCTAssertEqual(vm.wines.count, 1, "duplicate wine_id must not append twice")
    }

    func testScanNoWinesSetsHelpfulError() async {
        let body = sse([("complete", #"{"wine_count":0,"cache_hits":0,"scan_id":"s1"}"#)])
        let vm = makeViewModel()
        await runScan(body, on: vm)

        XCTAssertTrue(vm.wines.isEmpty)
        XCTAssertEqual(vm.errorMessage, "No wines found — try a flatter angle or better lighting")
    }

    func testScanOllamaDownErrorSurfacesServeHint() async {
        let body = sse([
            ("error", #"{"code":"OLLAMA_DOWN","message":"connection refused"}"#),
            ("complete", #"{"wine_count":0,"cache_hits":0,"scan_id":"s1"}"#),
        ])
        let vm = makeViewModel()
        await runScan(body, on: vm)

        XCTAssertTrue(
            vm.errorMessage?.contains("ollama serve") ?? false,
            "OLLAMA_DOWN must surface the serve hint; got: \(vm.errorMessage ?? "nil")")
    }

    func testScanGenericErrorCodeSurfacesCodeAndMessage() async {
        let body = sse([
            ("error", #"{"code":"WEIRD_FAILURE","message":"something odd"}"#),
            ("complete", #"{"wine_count":0,"cache_hits":0,"scan_id":"s1"}"#),
        ])
        let vm = makeViewModel()
        await runScan(body, on: vm)

        let msg = vm.errorMessage ?? ""
        XCTAssertTrue(
            msg.contains("WEIRD_FAILURE"), "generic error must include the code; got: \(msg)")
        XCTAssertTrue(
            msg.contains("something odd"), "generic error must include the message; got: \(msg)")
    }

    func testScanStatusAnalyzingAdvancesProgress() async {
        // status with no wines and no complete: progress advances to the analyzing
        // stage (0.7) and the loop's no-wines fallback fires. The backend sends the
        // stage marker as a raw (unquoted) string — see _sse in routers/scan.py.
        let body = sse([("status", "analyzing")])
        let vm = makeViewModel()
        await runScan(body, on: vm)

        XCTAssertEqual(vm.scanProgress, 0.7, accuracy: 0.001)
        XCTAssertTrue(vm.wines.isEmpty)
    }

    func testScanPingAdvancesProgress() async {
        // A ": ready" comment line is the first-byte flush → .ping (progress 0.4).
        let vm = makeViewModel()
        await runScan(": ready\n\n", on: vm)

        XCTAssertEqual(vm.scanProgress, 0.4, accuracy: 0.001)
    }

    func testScanImagePlaceholderLeavesNoImage() async {
        let body = sse([
            ("wine", #"{"name":"Opus One","confidence":0.9,"wine_id":"w1"}"#),
            ("image", #"{"wine_id":"w1","url":"http://x/img.jpg","placeholder":true}"#),
            ("complete", #"{"wine_count":1,"cache_hits":0,"scan_id":"s1"}"#),
        ])
        let vm = makeViewModel()
        await runScan(body, on: vm)

        XCTAssertEqual(vm.wines.count, 1)
        XCTAssertNil(vm.wines[0].imageData, "placeholder image must not set image data")
        XCTAssertFalse(vm.wines[0].isLoading, "placeholder is a terminal (non-loading) state")
    }

    func testScanImageReadyAttachesFetchedBytes() async {
        let imageBytes = Data([0xFF, 0xD8, 0xAB, 0xCD, 0xFF, 0xD9])
        let body = sse([
            ("wine", #"{"name":"Opus One","confidence":0.9,"wine_id":"w1"}"#),
            ("image", #"{"wine_id":"w1","url":"http://x/img.jpg","placeholder":false}"#),
            ("complete", #"{"wine_count":1,"cache_hits":1,"scan_id":"s1"}"#),
        ])
        let vm = makeViewModel()
        await runScan(body, on: vm, imageBytes: imageBytes)

        XCTAssertEqual(
            vm.wines[0].imageData, imageBytes,
            "a non-placeholder image event must fetch and attach the bytes")
    }

    func testScanNotesEventAttachesTastingNoteAndPairings() async {
        let body = sse([
            ("wine", #"{"name":"Opus One","confidence":0.9,"wine_id":"w1"}"#),
            ("notes", #"{"wine_id":"w1","tasting_note":"Rich and dark.","pairings":["Steak"]}"#),
            ("complete", #"{"wine_count":1,"cache_hits":1,"scan_id":"s1"}"#),
        ])
        let vm = makeViewModel()
        await runScan(body, on: vm)

        XCTAssertEqual(vm.wines[0].wine.tastingNote, "Rich and dark.")
        XCTAssertEqual(vm.wines[0].wine.pairings, ["Steak"])
        XCTAssertTrue(vm.wines[0].hasNotes, "a streamed tasting note must flip hasNotes true")
    }

    func testNotesResolveByStableIdForDetailView() async {
        // WineDetailView resolves live state by snapshot.id so a card opened before
        // its tasting note streams in still updates (the snapshot itself never does).
        // That contract holds only if attaching a note preserves the wine's id — pin
        // it: capture the id, then prove the lookup surfaces the streamed note.
        let body = sse([
            ("wine", #"{"name":"Opus One","confidence":0.9,"wine_id":"w1"}"#),
            ("notes", #"{"wine_id":"w1","tasting_note":"Rich and dark.","pairings":["Steak"]}"#),
            ("complete", #"{"wine_count":1,"cache_hits":1,"scan_id":"s1"}"#),
        ])
        let vm = makeViewModel()
        await runScan(body, on: vm)

        let snapshotId = vm.wines[0].id
        let live = vm.wines.first(where: { $0.id == snapshotId })
        XCTAssertEqual(
            live?.wine.tastingNote, "Rich and dark.",
            "live lookup by snapshot id must surface the streamed note")
        XCTAssertTrue(live?.hasNotes ?? false, "resolved live state must report hasNotes")
    }

    func testClearResetsWinesSelectionAndError() async {
        let body = sse([
            ("wine", #"{"name":"Opus One","confidence":0.9,"wine_id":"w1"}"#),
            ("complete", #"{"wine_count":1,"cache_hits":0,"scan_id":"s1"}"#),
        ])
        let vm = makeViewModel()
        await runScan(body, on: vm)
        vm.selectedWine = vm.wines.first?.wine
        vm.errorMessage = "stale error"

        vm.clear()

        XCTAssertTrue(vm.wines.isEmpty)
        XCTAssertNil(vm.selectedWine)
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isScanning)
    }
}
