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

    // MARK: - Reconnect detection

    func testStreamClosesWithoutCompleteSetNotesIncomplete() async {
        let vm = WineListViewModel(backend: MockBackendClient(events: [makeWineEvent()]))
        await vm.scan(photoData: Data())
        XCTAssertTrue(vm.notesIncomplete, "notesIncomplete should be true when stream closes without event:complete")
    }

    func testStreamWithCompleteDoesNotSetNotesIncomplete() async {
        let vm = WineListViewModel(backend: MockBackendClient(events: [makeWineEvent(), makeCompleteEvent()]))
        await vm.scan(photoData: Data())
        XCTAssertFalse(vm.notesIncomplete, "notesIncomplete should stay false when stream completes cleanly")
    }

    func testNoWinesDoesNotSetNotesIncomplete() async {
        let vm = WineListViewModel(backend: MockBackendClient(events: []))
        await vm.scan(photoData: Data())
        XCTAssertFalse(vm.notesIncomplete, "notesIncomplete should stay false when no wines were extracted")
    }

    func testStreamThrowsAfterWineEventSetsNotesIncomplete() async {
        let vm = WineListViewModel(
            backend: MockBackendClient(
                events: [makeWineEvent()],
                error: BackendError.unreachable("mock error")
            ))
        await vm.scan(photoData: Data())
        XCTAssertTrue(
            vm.notesIncomplete,
            "notesIncomplete should be true when stream throws after extracting wines")
    }

    func testClearResetsNotesIncomplete() async {
        let vm = WineListViewModel(backend: MockBackendClient(events: [makeWineEvent()]))
        await vm.scan(photoData: Data())
        XCTAssertTrue(vm.notesIncomplete)
        vm.clear()
        XCTAssertFalse(vm.notesIncomplete, "clear() must reset notesIncomplete")
    }

    // MARK: - Cancel on dismiss

    func testWineListViewModelCancelOnDismiss() async {
        // AsyncThrowingStream.next() returns nil (stream end) when the consuming Task is
        // cancelled, so the for-try-await loop exits normally. isScanning must still be
        // reset to false and notesIncomplete must stay false (no wines were extracted).
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
        let scanTask = Task { await vm.scan(photoData: Data()) }

        // Yield to let the scan task start and set isScanning = true
        try? await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertTrue(vm.isScanning, "scan should be in-progress before cancel")

        scanTask.cancel()
        await scanTask.value

        XCTAssertFalse(vm.isScanning, "isScanning must reset to false after task cancellation")
        XCTAssertFalse(vm.notesIncomplete, "notesIncomplete must stay false when no wines were extracted")
    }
}
