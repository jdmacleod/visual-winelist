// iOS tests run via:
//   xcodebuild test -package-path ios \
//     -destination "platform=iOS Simulator,name=iPhone 16"
//
// `swift test` on macOS will not work because VisualWinelistIOS links UIKit.

import XCTest

@testable import VisualWinelistIOS

// MARK: - MockProtocolRegistry

/// Actor-isolated registry for MockURLProtocol state. Using an actor eliminates
/// the @unchecked Sendable suppressor that was required when static vars were used.
/// Tests set state via async setX methods; startLoading() reads via snapshot().
struct MockProtocolSnapshot {
    let handler: ((URLRequest) -> (HTTPURLResponse, Data))?
    let holdLoading: Bool
    let onStartLoading: (() -> Void)?
    let chunks: [Data]?
    let errorToThrow: Error?
}

actor MockProtocolRegistry {
    static let shared = MockProtocolRegistry()

    var handler: ((URLRequest) -> (HTTPURLResponse, Data))?
    var holdLoading = false
    var onStartLoading: (() -> Void)?
    var chunks: [Data]?
    var errorToThrow: Error?

    func setHandler(_ newHandler: @escaping (URLRequest) -> (HTTPURLResponse, Data)) { handler = newHandler }
    func setHoldLoading(_ enabled: Bool) { holdLoading = enabled }
    func setOnStartLoading(_ block: (() -> Void)?) { onStartLoading = block }
    func setChunks(_ data: [Data]?) { chunks = data }
    func setErrorToThrow(_ error: Error?) { errorToThrow = error }

    func reset() {
        handler = nil
        holdLoading = false
        onStartLoading = nil
        chunks = nil
        errorToThrow = nil
    }

    func snapshot() -> MockProtocolSnapshot {
        MockProtocolSnapshot(
            handler: handler,
            holdLoading: holdLoading,
            onStartLoading: onStartLoading,
            chunks: chunks,
            errorToThrow: errorToThrow
        )
    }
}

// MARK: - MockURLProtocol

final class MockURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Task {
            let state = await MockProtocolRegistry.shared.snapshot()
            state.onStartLoading?()
            if let error = state.errorToThrow {
                client?.urlProtocol(self, didFailWithError: error)
                return
            }
            guard !state.holdLoading else { return }
            guard let handler = state.handler else {
                client?.urlProtocol(self, didFailWithError: URLError(.unknown))
                return
            }
            let (response, data) = handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let chunks = state.chunks {
                for chunk in chunks {
                    client?.urlProtocol(self, didLoad: chunk)
                }
            } else {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

// MARK: - Tests

final class IOSTestSuite: XCTestCase {

    override func tearDown() async throws {
        await MockProtocolRegistry.shared.reset()
        try await super.tearDown()
    }

    // MARK: - SSEParser: basic wine event

    func testSSEParserParsesWineEvent() {
        var parser = SSEParser()
        XCTAssertNil(parser.feed(line: "event: wine"))
        XCTAssertNil(parser.feed(line: #"data: {"name":"Opus One","confidence":0.9}"#))
        let result = parser.feed(line: "")
        guard case .wine(let wine) = result else {
            XCTFail("expected .wine, got \(String(describing: result))")
            return
        }
        XCTAssertEqual(wine.name, "Opus One")
        XCTAssertEqual(wine.confidence, 0.9, accuracy: 0.001)
    }

    // MARK: - SSEParser: multi-line data: concatenation (regression test for clobbering bug)

    func testSSEParserMultilineData() {
        // SSE spec: multiple data: fields for one event must be concatenated with LF.
        // The bug (data = value instead of data += "\n" + value) overwrites the first
        // fragment, leaving invalid JSON that cannot decode → returns nil.
        var parser = SSEParser()
        XCTAssertNil(parser.feed(line: "event: wine"))
        XCTAssertNil(parser.feed(line: #"data: {"name":"Margaux","#))
        XCTAssertNil(parser.feed(line: #"data: "confidence":0.9}"#))
        let result = parser.feed(line: "")
        guard case .wine(let wine) = result else {
            XCTFail(
                "multi-line data: fields must concatenate with \\n; got \(String(describing: result))"
            )
            return
        }
        XCTAssertEqual(wine.name, "Margaux")
    }

    // MARK: - SSEParser: malformed JSON → parseError

    func testSSEParserMalformedJsonReturnsParseError() {
        var parser = SSEParser()
        _ = parser.feed(line: "event: wine")
        _ = parser.feed(line: "data: not valid json {{")
        let result = parser.feed(line: "")
        guard case .parseError(let desc) = result else {
            XCTFail("malformed JSON should return .parseError, got \(String(describing: result))")
            return
        }
        XCTAssertTrue(desc.hasPrefix("wine:"), "parseError description should include event type; got: \(desc)")
    }

    // MARK: - NotesSSEPayload: absent pairings key defaults to []

    func testNotesPayloadDefaultsPairingsWhenKeyAbsent() {
        var parser = SSEParser()
        let json = #"{"wine_id":"abc","tasting_note":"Rich."}"#
        _ = parser.feed(line: "event: notes")
        _ = parser.feed(line: "data: \(json)")
        let result = parser.feed(line: "")
        guard case .notes(let payload) = result else {
            XCTFail("expected .notes, got \(String(describing: result))")
            return
        }
        XCTAssertEqual(payload.pairings, [], "absent pairings key should default to empty array")
    }

    // MARK: - CompleteSSEPayload: decodes receive_ms + timing fields

    func testCompletePayloadDecodesReceiveMsAndTimingFields() {
        var parser = SSEParser()
        let json =
            #"{"wine_count":2,"cache_hits":1,"scan_id":"abc","receive_ms":123,"#
            + #""first_wine_ms":450,"brave_search_ms":80,"image_download_ms":210}"#
        _ = parser.feed(line: "event: complete")
        _ = parser.feed(line: "data: \(json)")
        let result = parser.feed(line: "")
        guard case .complete(let payload) = result else {
            XCTFail("expected .complete, got \(String(describing: result))")
            return
        }
        XCTAssertEqual(payload.receive_ms, 123, "receive_ms must decode from the complete event")
        XCTAssertEqual(payload.first_wine_ms, 450)
        XCTAssertEqual(payload.brave_search_ms, 80)
        XCTAssertEqual(payload.image_download_ms, 210)
    }

    // MARK: - CompleteSSEPayload: optional timing fields default to nil when absent

    func testCompletePayloadTimingFieldsNilWhenAbsent() {
        var parser = SSEParser()
        let json = #"{"wine_count":1,"cache_hits":0,"scan_id":"xyz"}"#
        _ = parser.feed(line: "event: complete")
        _ = parser.feed(line: "data: \(json)")
        let result = parser.feed(line: "")
        guard case .complete(let payload) = result else {
            XCTFail("expected .complete, got \(String(describing: result))")
            return
        }
        XCTAssertNil(payload.receive_ms, "absent receive_ms must decode as nil, not fail")
        XCTAssertNil(payload.first_wine_ms)
        XCTAssertNil(payload.brave_search_ms)
        XCTAssertEqual(payload.wine_count, 1)
    }

    // MARK: - IOSScanSession: receives wine event via MockURLProtocol

    func testIOSScanSessionReceivesWineEvent() async throws {
        let baseURL = URL(string: "http://localhost:8000")!
        let sseText = "event: wine\ndata: {\"name\":\"Test Wine\",\"confidence\":0.9}\n\n"
        let sseData = Data(sseText.utf8)

        await MockProtocolRegistry.shared.setHandler { _ in
            let response = HTTPURLResponse(
                url: baseURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, sseData)
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]

        let request = URLRequest(url: baseURL.appendingPathComponent("scan"))
        let (stream, _) = IOSScanSession.make(request: request, configuration: config)

        var events: [SSEEvent] = []
        for try await event in stream {
            events.append(event)
        }

        guard let first = events.first, case .wine(let wine) = first else {
            XCTFail("expected a .wine SSEEvent, got: \(events)")
            return
        }
        XCTAssertEqual(wine.name, "Test Wine")
    }

    // MARK: - SettingsBundle: StartupValidator reads BACKEND_URL from UserDefaults

    func testBackendURLFromUserDefaults() {
        let key = "BACKEND_URL"
        let expected = "http://192.168.1.1:8000"
        UserDefaults.standard.set(expected, forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let url = StartupValidator.backendURL()
        XCTAssertEqual(url?.absoluteString, expected)
    }

    func testBackendURLEmptyReturnsNil() {
        let key = "BACKEND_URL"
        UserDefaults.standard.set("", forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        XCTAssertNil(StartupValidator.backendURL(), "empty BACKEND_URL should return nil")
    }

    func testBackendURLInvalidURLReturnsNil() {
        let key = "BACKEND_URL"
        UserDefaults.standard.set("not-a-url:::", forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        XCTAssertNil(
            StartupValidator.backendURL(), "invalid URL format should return nil (no scheme)")
    }

    // MARK: - IOSScanSession: multibyte UTF-8 character split across delivery boundaries

    func testIOSScanSessionMultibyteCharacterAcrossChunkBoundary() async throws {
        // "Château" contains 'â' (U+00E2), which UTF-8 encodes as 0xC3 0xA2.
        // Splitting the payload between those two bytes triggers the bug in the
        // old String-based lineBuffer: String(data:encoding:) returns nil for an
        // incomplete multibyte sequence, silently dropping the entire chunk.
        // The Data-based buffer accumulates raw bytes before decoding, so it
        // reassembles the character correctly regardless of delivery boundaries.
        let sseText = "event: wine\ndata: {\"name\":\"Ch\u{00e2}teau\",\"confidence\":0.9}\n\n"
        let allBytes = Data(sseText.utf8)

        // Locate â (0xC3 0xA2) and split after the first byte (0xC3).
        var splitIndex: Int?
        for i in allBytes.indices.dropLast() {
            let j = allBytes.index(after: i)
            if allBytes[i] == 0xC3 && allBytes[j] == 0xA2 {
                splitIndex = j
                break
            }
        }
        guard let split = splitIndex else {
            XCTFail("â bytes not found in test payload")
            return
        }

        let baseURL = URL(string: "http://localhost:8000")!
        await MockProtocolRegistry.shared.setHandler { _ in
            let response = HTTPURLResponse(
                url: baseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())  // data ignored; chunks drives delivery
        }
        await MockProtocolRegistry.shared.setChunks(
            [Data(allBytes[..<split]), Data(allBytes[split...])])

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let request = URLRequest(url: baseURL.appendingPathComponent("scan"))
        let (stream, _) = IOSScanSession.make(request: request, configuration: config)

        var events: [SSEEvent] = []
        for try await event in stream {
            events.append(event)
        }

        guard let first = events.first, case .wine(let wine) = first else {
            XCTFail("multibyte split: expected .wine event, got: \(events)")
            return
        }
        XCTAssertEqual(wine.name, "Ch\u{00e2}teau", "â must survive URLSession chunk boundary split")
    }

    // MARK: - IOSScanSession: cancel stops stream cleanly

    func testIOSScanSessionCancelStopsStream() async {
        // holdLoading=true makes startLoading() return without delivering data.
        // Cancelling the task triggers NSURLErrorCancelled → IOSScanSession maps
        // this to continuation.finish() (a clean end, not an error throw).
        //
        // onStartLoading must be set before IOSScanSession.make() so it is in
        // place when URLSession dispatches startLoading() on its background queue.
        let started = expectation(description: "URLSession startLoading called")
        await MockProtocolRegistry.shared.setHoldLoading(true)
        await MockProtocolRegistry.shared.setOnStartLoading { started.fulfill() }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]

        let request = URLRequest(url: URL(string: "http://localhost:8000/scan")!)
        let (stream, session) = IOSScanSession.make(request: request, configuration: config)

        var events: [SSEEvent] = []
        let consumeTask = Task {
            do {
                for try await event in stream { events.append(event) }
            } catch {
                XCTFail("stream must end cleanly after cancel, not throw: \(error)")
            }
        }

        await fulfillment(of: [started], timeout: 2.0)
        session.cancel()
        await consumeTask.value

        XCTAssertEqual(events.count, 0, "cancelled session should yield no events")
    }

    // MARK: - IOSScanSession: 1MB lineBuffer cap mid-chunk

    func testIOSScanSessionLineBufferCapMidChunkDiscardsOversizedLine() async throws {
        // Deliver a single Data chunk containing: 1MB+ garbage (no newline) + newline + valid SSE.
        // The new segment-by-segment logic must discard the oversized pseudo-line and still
        // yield the valid complete event that follows in the same delivery chunk.
        let garbage = Data(repeating: UInt8(ascii: "x"), count: 1_048_577)
        let valid = Data("event: complete\ndata: {\"wine_count\":1,\"cache_hits\":0,\"scan_id\":\"y\"}\n\n".utf8)
        let payload = garbage + Data([UInt8(ascii: "\n")]) + valid

        let baseURL = URL(string: "http://localhost:8000")!
        await MockProtocolRegistry.shared.setHandler { _ in
            let response = HTTPURLResponse(
                url: baseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())  // data ignored; chunks drives delivery
        }
        await MockProtocolRegistry.shared.setChunks([payload])  // single chunk with both garbage and valid SSE

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let request = URLRequest(url: baseURL.appendingPathComponent("scan"))
        let (stream, _) = IOSScanSession.make(request: request, configuration: config)

        var events: [SSEEvent] = []
        for try await event in stream {
            events.append(event)
        }

        XCTAssertEqual(events.count, 1, "oversized line in same chunk must be dropped; only complete event survives")
        guard case .complete(let payload) = events.first else {
            XCTFail("Expected .complete event after mid-chunk lineBuffer cap reset, got: \(events)")
            return
        }
        XCTAssertEqual(payload.wine_count, 1)
    }

    // MARK: - iOS BackendClient: checkHealth with injectable session

    func testIOSCheckHealth200() async throws {
        let baseURL = URL(string: "http://localhost:8000")!
        let healthJSON = Data(#"{"status":"ok","ollama":true,"brave_key":true}"#.utf8)
        await MockProtocolRegistry.shared.setHandler { _ in
            let response = HTTPURLResponse(
                url: baseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, healthJSON)
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let client = BackendClient(baseURL: baseURL, session: URLSession(configuration: config))
        let health = try await client.checkHealth()
        XCTAssertTrue(health.isOK)
    }

    func testIOSCheckHealthURLError() async {
        let baseURL = URL(string: "http://localhost:8000")!
        await MockProtocolRegistry.shared.setErrorToThrow(URLError(.notConnectedToInternet))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let client = BackendClient(baseURL: baseURL, session: URLSession(configuration: config))
        do {
            _ = try await client.checkHealth()
            XCTFail("expected BackendError.unreachable")
        } catch BackendError.unreachable {
            // pass
        } catch {
            XCTFail("expected BackendError.unreachable, got \(error)")
        }
    }

    // MARK: - iOS BackendClient: fetchImage with injectable session

    func testIOSFetchImage200() async throws {
        let baseURL = URL(string: "http://localhost:8000")!
        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0])
        await MockProtocolRegistry.shared.setHandler { _ in
            let response = HTTPURLResponse(
                url: baseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, imageData)
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let client = BackendClient(baseURL: baseURL, session: URLSession(configuration: config))
        let data = try await client.fetchImage(wineId: "abc")
        XCTAssertEqual(data, imageData)
    }

    func testIOSFetchImageURLError() async {
        let baseURL = URL(string: "http://localhost:8000")!
        await MockProtocolRegistry.shared.setErrorToThrow(URLError(.timedOut))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let client = BackendClient(baseURL: baseURL, session: URLSession(configuration: config))
        do {
            _ = try await client.fetchImage(wineId: "abc")
            XCTFail("expected BackendError.unreachable")
        } catch BackendError.unreachable {
            // pass
        } catch {
            XCTFail("expected BackendError.unreachable, got \(error)")
        }
    }

    // MARK: - iOS BackendClient: scan() forwards injected session configuration

    func testIOSBackendClientScanForwardsSessionConfiguration() async throws {
        // Verify that BackendClient.scan() passes session.configuration to IOSScanSession.make().
        // Before the fix, IOSScanSession.make(request:) used .default config, so MockURLProtocol
        // could not intercept scan requests even when an injectable session was provided.
        let baseURL = URL(string: "http://localhost:8000")!
        let sseText = "event: wine\ndata: {\"name\":\"Forwarded Session Wine\",\"confidence\":0.9}\n\n"
        await MockProtocolRegistry.shared.setHandler { _ in
            let response = HTTPURLResponse(url: baseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(sseText.utf8))
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let client = BackendClient(baseURL: baseURL, session: URLSession(configuration: config))

        let (stream, _) = client.scan(photoData: Data())
        var events: [SSEEvent] = []
        do {
            for try await event in stream { events.append(event) }
        } catch {}

        guard let first = events.first, case .wine(let wine) = first else {
            XCTFail(
                "scan() must route through injected session; MockURLProtocol received no request — got \(events)"
            )
            return
        }
        XCTAssertEqual(wine.name, "Forwarded Session Wine")
    }

    // MARK: - iOS BackendClient: URLError.cancelled re-thrown as CancellationError

    func testIOSCheckHealthCancelledRethrowsCancellationError() async {
        let baseURL = URL(string: "http://localhost:8000")!
        await MockProtocolRegistry.shared.setErrorToThrow(URLError(.cancelled))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let client = BackendClient(baseURL: baseURL, session: URLSession(configuration: config))
        do {
            _ = try await client.checkHealth()
            XCTFail("Expected CancellationError when URLError.cancelled is thrown")
        } catch is CancellationError {
            // pass — cancellation propagates correctly
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    func testIOSFetchImageCancelledRethrowsCancellationError() async {
        let baseURL = URL(string: "http://localhost:8000")!
        await MockProtocolRegistry.shared.setErrorToThrow(URLError(.cancelled))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let client = BackendClient(baseURL: baseURL, session: URLSession(configuration: config))
        do {
            _ = try await client.fetchImage(wineId: "abc")
            XCTFail("Expected CancellationError when URLError.cancelled is thrown")
        } catch is CancellationError {
            // pass — cancellation propagates correctly
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    func testIOSFetchImage404() async {
        let baseURL = URL(string: "http://localhost:8000")!
        await MockProtocolRegistry.shared.setHandler { _ in
            let response = HTTPURLResponse(
                url: baseURL, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let client = BackendClient(baseURL: baseURL, session: URLSession(configuration: config))
        do {
            _ = try await client.fetchImage(wineId: "abc")
            XCTFail("expected BackendError.httpError(404)")
        } catch BackendError.httpError(let code) {
            XCTAssertEqual(code, 404)
        } catch {
            XCTFail("expected BackendError.httpError(404), got \(error)")
        }
    }
}
