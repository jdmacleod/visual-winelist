// iOS tests run via:
//   xcodebuild test -package-path ios \
//     -destination "platform=iOS Simulator,name=iPhone 16"
//
// `swift test` on macOS will not work because VisualWinelistIOS links UIKit.

import XCTest

@testable import VisualWinelistIOS

// MARK: - MockURLProtocol

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url ?? URL(string: "http://localhost:8000")!
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Tests

final class IOSTestSuite: XCTestCase {

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
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

    // MARK: - IOSScanSession: receives wine event via MockURLProtocol

    func testIOSScanSessionReceivesWineEvent() async throws {
        let baseURL = URL(string: "http://localhost:8000")!
        let sseText = "event: wine\ndata: {\"name\":\"Test Wine\",\"confidence\":0.9}\n\n"
        let sseData = Data(sseText.utf8)

        MockURLProtocol.handler = { _ in
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
}
