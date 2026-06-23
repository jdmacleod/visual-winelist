import XCTest

@testable import VisualWinelist

@MainActor
final class WineListViewModelTests: XCTestCase {

    // MARK: - Mock

    private struct MockBackendClient: BackendClientProtocol {
        let events: [SSEEvent]
        let scanError: Error?

        init(events: [SSEEvent] = [], error: Error? = nil) {
            self.events = events
            self.scanError = error
        }

        func checkHealth() async throws -> HealthResponse {
            throw BackendError.unreachable("mock")
        }

        func scan(photoData: Data) -> AsyncThrowingStream<SSEEvent, Error> {
            let events = self.events
            let scanError = self.scanError
            return AsyncThrowingStream { continuation in
                for event in events { continuation.yield(event) }
                if let error = scanError {
                    continuation.finish(throwing: error)
                } else {
                    continuation.finish()
                }
            }
        }

        func fetchImage(wineId: String) async throws -> Data { Data() }
    }

    private func makeWineEvent() -> SSEEvent {
        .wine(WineObject(name: "Test Wine", confidence: 0.95))
    }

    private func makeCompleteEvent() -> SSEEvent {
        .complete(
            CompleteSSEPayload(
                wine_count: 1, cache_hits: 0, scan_id: "test", ollama_ms: nil, image_ms: nil, sommelier_ms: nil,
                total_ms: nil))
    }

    // MARK: - Per-wine tasting note state

    func testWineHasNoTastingNoteWhenNoNotesEventReceived() async {
        let vm = WineListViewModel(backend: MockBackendClient(events: [makeWineEvent()]))
        await vm.scan(photoData: Data())
        XCTAssertNil(vm.wines.first?.wine.tastingNote, "wine has no tastingNote when no notes event received")
    }

    func testScanCompletesWithIsScanningFalse() async {
        let vm = WineListViewModel(backend: MockBackendClient(events: [makeWineEvent(), makeCompleteEvent()]))
        await vm.scan(photoData: Data())
        XCTAssertFalse(vm.isScanning, "isScanning must be false after scan completes")
    }

    func testNoWinesExtractedSetsErrorMessage() async {
        let vm = WineListViewModel(backend: MockBackendClient(events: []))
        await vm.scan(photoData: Data())
        XCTAssertNotNil(vm.errorMessage, "errorMessage should be set when no wines were extracted")
    }

    func testStreamThrowsAfterWineEventSetsErrorMessage() async {
        let vm = WineListViewModel(
            backend: MockBackendClient(
                events: [makeWineEvent()],
                error: BackendError.unreachable("mock error")
            ))
        await vm.scan(photoData: Data())
        XCTAssertNotNil(vm.errorMessage, "errorMessage should be set when stream throws")
    }

    func testClearResetsState() async {
        let vm = WineListViewModel(backend: MockBackendClient(events: [makeWineEvent()]))
        await vm.scan(photoData: Data())
        XCTAssertFalse(vm.wines.isEmpty)
        vm.clear()
        XCTAssertTrue(vm.wines.isEmpty, "clear() must reset wines")
        XCTAssertNil(vm.errorMessage, "clear() must reset errorMessage")
        XCTAssertFalse(vm.isScanning, "clear() must leave isScanning false")
    }

    // MARK: - Error code routing

    private func makeErrorEvent(code: String, message: String = "test message") -> SSEEvent {
        .error(ErrorSSEPayload(code: code, wine_index: nil, message: message))
    }

    func testOllamaDownSetsActionableErrorMessage() async {
        let vm = WineListViewModel(backend: MockBackendClient(events: [makeErrorEvent(code: "OLLAMA_DOWN")]))
        await vm.scan(photoData: Data())
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(vm.errorMessage?.contains("ollama serve") == true, "OLLAMA_DOWN message must include run hint")
    }

    func testOllamaTimeoutSetsActionableErrorMessage() async {
        let vm = WineListViewModel(backend: MockBackendClient(events: [makeErrorEvent(code: "OLLAMA_TIMEOUT")]))
        await vm.scan(photoData: Data())
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(
            vm.errorMessage?.contains("timed out") == true,
            "OLLAMA_TIMEOUT message must describe the timeout condition")
    }

    func testUnknownErrorCodeSetsGenericErrorMessage() async {
        let vm = WineListViewModel(
            backend: MockBackendClient(events: [makeErrorEvent(code: "PARSE_ERROR", message: "bad json")]))
        await vm.scan(photoData: Data())
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(
            vm.errorMessage?.contains("PARSE_ERROR") == true,
            "Unknown error code must be included in the generic fallback message")
    }

    // MARK: - isScanning unblocks at .complete, not after image fetches

    func testIsScanningFalseAtCompleteEventBeforeImageFetchReturns() async {
        // Regression: isScanning used to stay true until all image fetches finished (defer).
        // After fix, .complete sets isScanning=false so action buttons unblock immediately.
        struct SlowClient: BackendClientProtocol {
            func checkHealth() async throws -> HealthResponse { throw BackendError.unreachable("") }
            func scan(photoData: Data) -> AsyncThrowingStream<SSEEvent, Error> {
                AsyncThrowingStream { continuation in
                    // Yield events from a background task so isScanning=true is observable
                    // before .complete fires (synchronous yield drains before the poll loop runs).
                    Task {
                        let wine = WineObject(name: "Test Wine", confidence: 0.9, wineId: "w1")
                        let imagePayload = ImageSSEPayload(wine_id: "w1", url: "/images/w1", placeholder: false)
                        let complete = CompleteSSEPayload(
                            wine_count: 1, cache_hits: 0, scan_id: "test",
                            ollama_ms: nil, image_ms: nil, sommelier_ms: nil, total_ms: nil)
                        continuation.yield(.wine(wine))
                        continuation.yield(.image(imagePayload))
                        // 50ms gap so isScanning=true can be observed before .complete fires.
                        try? await Task.sleep(nanoseconds: 50_000_000)
                        continuation.yield(.complete(complete))
                        continuation.finish()
                    }
                }
            }
            func fetchImage(wineId: String) async throws -> Data {
                try await Task.sleep(nanoseconds: 500_000_000)  // 500ms — still in-flight when .complete fires
                return Data()
            }
        }

        let vm = WineListViewModel(backend: SlowClient())
        let outerTask = Task { await vm.scan(photoData: Data()) }

        // Wait for scan to start (isScanning goes true once .wine is processed).
        for _ in 0..<20 {
            if vm.isScanning { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(vm.isScanning, "scan should have started")

        // Poll up to 200ms for isScanning to flip false (at .complete, before 500ms fetchImage).
        for _ in 0..<40 {
            if !vm.isScanning { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertFalse(vm.isScanning, "isScanning must be false after .complete even while image fetches are pending")

        await outerTask.value
        XCTAssertEqual(vm.wines.count, 1, "scan must have produced wines")
    }

    // MARK: - Cancel on dismiss

    func testWineListViewModelCancelOnDismiss() async {
        struct SlowClient: BackendClientProtocol {
            func checkHealth() async throws -> HealthResponse { throw BackendError.unreachable("") }
            func scan(photoData: Data) -> AsyncThrowingStream<SSEEvent, Error> {
                AsyncThrowingStream { continuation in
                    Task {
                        try? await Task.sleep(nanoseconds: 60_000_000_000)
                        continuation.finish()
                    }
                }
            }
            func fetchImage(wineId: String) async throws -> Data { Data() }
        }

        let vm = WineListViewModel(backend: SlowClient())
        let outerTask = Task { await vm.scan(photoData: Data()) }

        // Poll until isScanning=true (up to 100ms) so we don't race against task startup.
        for _ in 0..<20 {
            if vm.isScanning { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(vm.isScanning, "scan should be in-progress before cancel")

        // Cancel via ViewModel so the stored scanTask is cancelled, then await completion.
        vm.cancelScan()
        await outerTask.value

        XCTAssertFalse(vm.isScanning, "isScanning must reset to false after cancelScan()")
    }
}
