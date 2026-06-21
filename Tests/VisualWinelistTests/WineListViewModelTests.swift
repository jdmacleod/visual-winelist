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

    func testClearResetsNotesIncomplete() async {
        let vm = WineListViewModel(backend: MockBackendClient(events: [makeWineEvent()]))
        await vm.scan(photoData: Data())
        XCTAssertTrue(vm.notesIncomplete)
        vm.clear()
        XCTAssertFalse(vm.notesIncomplete, "clear() must reset notesIncomplete")
    }
}
