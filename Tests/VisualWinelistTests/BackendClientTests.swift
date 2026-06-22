import XCTest

@testable import VisualWinelist

// MARK: - URLProtocol stub

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    // FIXME: static var is not parallel-test-safe — see TODOS.md
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data?))?
    /// When true, startLoading() returns without delivering data (simulates a hanging server).
    static var holdLoading = false
    /// Called at the start of startLoading(), before any data delivery.
    static var onStartLoading: (() -> Void)?
    /// Called when the URLSession task is cancelled (via stopLoading).
    static var onStopLoading: (() -> Void)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        MockURLProtocol.onStartLoading?()
        if MockURLProtocol.holdLoading { return }
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data = data {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        MockURLProtocol.onStopLoading?()
    }
}

// MARK: - Tests

final class BackendClientTests: XCTestCase {
    private var session: URLSession!
    private let baseURL = URL(string: "http://localhost:8000")!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        MockURLProtocol.holdLoading = false
        MockURLProtocol.onStartLoading = nil
        MockURLProtocol.onStopLoading = nil
        session = nil
        super.tearDown()
    }

    private func makeClient() -> BackendClient {
        BackendClient(baseURL: baseURL, session: session)
    }

    private func makeResponse(statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: baseURL, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    }

    // MARK: - HTTP error handling

    func testScan503ThrowsScannerBusy() async throws {
        MockURLProtocol.handler = { [self] _ in (makeResponse(statusCode: 503), nil) }
        var caught: Error?
        do {
            for try await _ in makeClient().scan(photoData: Data()) {}
        } catch {
            caught = error
        }
        guard case .scannerBusy = caught as? BackendError else {
            XCTFail("Expected BackendError.scannerBusy, got \(String(describing: caught))")
            return
        }
    }

    func testScan403ThrowsHttpError() async throws {
        MockURLProtocol.handler = { [self] _ in (makeResponse(statusCode: 403), nil) }
        var caught: Error?
        do {
            for try await _ in makeClient().scan(photoData: Data()) {}
        } catch {
            caught = error
        }
        guard case .httpError(403) = caught as? BackendError else {
            XCTFail("Expected BackendError.httpError(403), got \(String(describing: caught))")
            return
        }
    }

    // MARK: - SSE byte-iteration parsing

    func testScanCompleteEventParsedFromStream() async throws {
        let sse = "event: complete\ndata: {\"wine_count\":2,\"cache_hits\":1,\"scan_id\":\"abc\"}\n\n"
        MockURLProtocol.handler = { [self] _ in
            (makeResponse(statusCode: 200), sse.data(using: .utf8))
        }
        var events: [SSEEvent] = []
        for try await event in makeClient().scan(photoData: Data()) {
            events.append(event)
        }
        XCTAssertEqual(events.count, 1)
        guard case .complete(let payload) = events[0] else {
            XCTFail("Expected .complete event, got \(events[0])")
            return
        }
        XCTAssertEqual(payload.wine_count, 2)
        XCTAssertEqual(payload.cache_hits, 1)
        XCTAssertEqual(payload.scan_id, "abc")
    }

    func testScanCRLFLineEndingsStrippedCorrectly() async throws {
        // Windows-style CRLF line endings must produce the same events as LF-only.
        // The byte-iteration loop strips \r before splitting on \n.
        let sse = "event: complete\r\ndata: {\"wine_count\":1,\"cache_hits\":0,\"scan_id\":\"x\"}\r\n\r\n"
        MockURLProtocol.handler = { [self] _ in
            (makeResponse(statusCode: 200), sse.data(using: .utf8))
        }
        var events: [SSEEvent] = []
        for try await event in makeClient().scan(photoData: Data()) {
            events.append(event)
        }
        XCTAssertEqual(events.count, 1)
        guard case .complete(let payload) = events[0] else {
            XCTFail("CR/LF stripping failed — expected .complete, got \(events[0])")
            return
        }
        XCTAssertEqual(payload.wine_count, 1)
    }

    func testScanPingEventYielded() async throws {
        let sse = ": ping\n\n"
        MockURLProtocol.handler = { [self] _ in
            (makeResponse(statusCode: 200), sse.data(using: .utf8))
        }
        var events: [SSEEvent] = []
        for try await event in makeClient().scan(photoData: Data()) {
            events.append(event)
        }
        XCTAssertEqual(events.count, 1)
        guard case .ping = events[0] else {
            XCTFail("Expected .ping event, got \(events[0])")
            return
        }
    }

    func testScanEmptyStreamFinishesWithoutError() async {
        MockURLProtocol.handler = { [self] _ in (makeResponse(statusCode: 200), Data()) }
        var events: [SSEEvent] = []
        do {
            for try await event in makeClient().scan(photoData: Data()) {
                events.append(event)
            }
        } catch {
            XCTFail("Empty stream should not throw: \(error)")
        }
        XCTAssertTrue(events.isEmpty)
    }

    // MARK: - Health check

    func testCheckHealthDecodesOKResponse() async throws {
        let json = "{\"status\":\"ok\",\"ollama\":true,\"brave_key\":true}".data(using: .utf8)!
        MockURLProtocol.handler = { [self] _ in (makeResponse(statusCode: 200), json) }
        let health = try await makeClient().checkHealth()
        XCTAssertEqual(health.status, "ok")
        XCTAssertTrue(health.ollama)
        XCTAssertTrue(health.isOK)
    }

    func testCheckHealth503ThrowsHttpError() async throws {
        MockURLProtocol.handler = { [self] _ in (makeResponse(statusCode: 503), nil) }
        do {
            _ = try await makeClient().checkHealth()
            XCTFail("Expected error for HTTP 503")
        } catch let error as BackendError {
            guard case .httpError(503) = error else {
                XCTFail("Expected httpError(503), got \(error)")
                return
            }
        }
    }

    // MARK: - Image fetch

    func testFetchImageReturnsDataOn200() async throws {
        let imageData = Data([0xFF, 0xD8, 0xFF])
        MockURLProtocol.handler = { [self] _ in (makeResponse(statusCode: 200), imageData) }
        let result = try await makeClient().fetchImage(wineId: "wine-abc")
        XCTAssertEqual(result, imageData)
    }

    func testFetchImage404ThrowsHttpError() async throws {
        MockURLProtocol.handler = { [self] _ in (makeResponse(statusCode: 404), nil) }
        do {
            _ = try await makeClient().fetchImage(wineId: "wine-abc")
            XCTFail("Expected error for HTTP 404")
        } catch let error as BackendError {
            guard case .httpError(404) = error else {
                XCTFail("Expected httpError(404), got \(error)")
                return
            }
        }
    }

    // MARK: - Cancellation propagation

    func testScanCancellationCancelsURLSessionTask() async {
        // Verify that cancelling the stream consumer also cancels the underlying
        // URLSession task. Without continuation.onTermination, the inner Task keeps
        // the URLSession connection open after the consumer exits, holding the
        // SCANNER_BUSY lock on the server for up to 300 seconds.
        let loadingStarted = expectation(description: "URLSession startLoading called")
        let taskCancelled = expectation(description: "URLSession stopLoading called after consumer cancel")

        MockURLProtocol.holdLoading = true
        MockURLProtocol.onStartLoading = { loadingStarted.fulfill() }
        MockURLProtocol.onStopLoading = { taskCancelled.fulfill() }

        let streamTask = Task {
            do {
                for try await _ in makeClient().scan(photoData: Data()) {}
            } catch {}
        }

        await fulfillment(of: [loadingStarted], timeout: 2.0)
        streamTask.cancel()
        await fulfillment(of: [taskCancelled], timeout: 2.0)
        await streamTask.value
    }

    // MARK: - URLError handling

    func testScanConnectionRefusedThrowsUnreachable() async throws {
        MockURLProtocol.handler = { _ in throw URLError(.cannotConnectToHost) }
        var caught: Error?
        do {
            for try await _ in makeClient().scan(photoData: Data()) {}
        } catch {
            caught = error
        }
        guard case .unreachable = caught as? BackendError else {
            XCTFail("Expected BackendError.unreachable, got \(String(describing: caught))")
            return
        }
    }

    // checkHealth() URLError → BackendError.unreachable
    func testCheckHealthURLErrorThrowsUnreachable() async {
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await makeClient().checkHealth()
            XCTFail("Expected BackendError.unreachable")
        } catch let error as BackendError {
            guard case .unreachable = error else {
                XCTFail("Expected .unreachable, got \(error)")
                return
            }
        } catch {
            XCTFail("Expected BackendError.unreachable, got \(error)")
        }
    }

    func testCheckHealthSecureConnectionFailedThrowsUnreachable() async {
        MockURLProtocol.handler = { _ in throw URLError(.secureConnectionFailed) }
        do {
            _ = try await makeClient().checkHealth()
            XCTFail("Expected BackendError.unreachable")
        } catch let error as BackendError {
            guard case .unreachable = error else {
                XCTFail("Expected .unreachable, got \(error)")
                return
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // fetchImage() URLError → BackendError.unreachable
    func testFetchImageURLErrorThrowsUnreachable() async {
        MockURLProtocol.handler = { _ in throw URLError(.timedOut) }
        do {
            _ = try await makeClient().fetchImage(wineId: "wine-abc")
            XCTFail("Expected BackendError.unreachable")
        } catch let error as BackendError {
            guard case .unreachable = error else {
                XCTFail("Expected .unreachable, got \(error)")
                return
            }
        } catch {
            XCTFail("Expected BackendError.unreachable, got \(error)")
        }
    }

    // lineBuffer 1MB cap: a line longer than 1,048,576 bytes must be silently
    // discarded rather than growing the buffer unboundedly. The cap resets the
    // buffer, so the oversized line produces no SSE event.
    func testScanLineBufferCapDiscardsOversizedLine() async throws {
        // Build a single SSE "line" that is > 1 MB (no newline in the garbage),
        // followed by a valid complete event separated by a real newline.
        let garbage = Data(repeating: UInt8(ascii: "x"), count: 1_048_577)
        let valid = Data("event: complete\ndata: {\"wine_count\":1,\"cache_hits\":0,\"scan_id\":\"z\"}\n\n".utf8)
        let payload = garbage + Data([UInt8(ascii: "\n")]) + valid

        MockURLProtocol.handler = { [self] _ in (makeResponse(statusCode: 200), payload) }
        var events: [SSEEvent] = []
        for try await event in makeClient().scan(photoData: Data()) {
            events.append(event)
        }
        // The garbage "line" is discarded; only the complete event survives.
        XCTAssertEqual(events.count, 1, "oversized line must be dropped; only the complete event should survive")
        guard case .complete = events[0] else {
            XCTFail("Expected .complete event after lineBuffer cap reset, got \(events[0])")
            return
        }
    }
}
