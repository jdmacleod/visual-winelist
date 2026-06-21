import XCTest
@testable import VisualWinelist

final class SSEParserTests: XCTestCase {

    // MARK: - Ping / comment

    func testCommentLineReturnsPing() {
        var parser = SSEParser()
        let result = parser.feed(line: ": ping")
        guard case .ping = result else { XCTFail("expected .ping, got \(String(describing: result))"); return }
    }

    func testBareColonReturnsPing() {
        var parser = SSEParser()
        let result = parser.feed(line: ":")
        guard case .ping = result else { XCTFail("expected .ping"); return }
    }

    // MARK: - wine event

    func testWineEventFullPayload() {
        var parser = SSEParser()
        let json = #"{"name":"Opus One","vintage":"2019","confidence":0.92}"#
        XCTAssertNil(parser.feed(line: "event: wine"))
        XCTAssertNil(parser.feed(line: "data: \(json)"))
        let result = parser.feed(line: "")
        guard case .wine(let wine) = result else { XCTFail("expected .wine"); return }
        XCTAssertEqual(wine.name, "Opus One")
        XCTAssertEqual(wine.vintage, "2019")
        XCTAssertEqual(wine.confidence, 0.92)
    }

    func testWineEventResetsStateAfterDispatch() {
        var parser = SSEParser()
        _ = parser.feed(line: "event: wine")
        _ = parser.feed(line: #"data: {"name":"A","confidence":0.9}"#)
        _ = parser.feed(line: "")

        // second event with only data: (no event: prefix) → should dispatch as "message" (unknown) → nil
        XCTAssertNil(parser.feed(line: #"data: {"name":"B","confidence":0.8}"#))
        let result = parser.feed(line: "")
        XCTAssertNil(result, "default event type 'message' should return nil (unknown event)")
    }

    // MARK: - image event

    func testImageEvent() {
        var parser = SSEParser()
        let json = #"{"wine_id":"abc123","url":"/wines/abc123/image","placeholder":false}"#
        _ = parser.feed(line: "event: image")
        _ = parser.feed(line: "data: \(json)")
        let result = parser.feed(line: "")
        guard case .image(let payload) = result else { XCTFail("expected .image"); return }
        XCTAssertEqual(payload.wine_id, "abc123")
        XCTAssertEqual(payload.url, "/wines/abc123/image")
        XCTAssertFalse(payload.placeholder)
    }

    func testImageEventWithPlaceholder() {
        var parser = SSEParser()
        let json = #"{"wine_id":"xyz","url":"/wines/xyz/image","placeholder":true}"#
        _ = parser.feed(line: "event: image")
        _ = parser.feed(line: "data: \(json)")
        let result = parser.feed(line: "")
        guard case .image(let payload) = result else { XCTFail("expected .image"); return }
        XCTAssertTrue(payload.placeholder)
    }

    // MARK: - notes event

    func testNotesEventWithPairings() {
        var parser = SSEParser()
        let json = #"{"wine_id":"abc","tasting_note":"Rich and velvety.","pairings":["lamb","duck","aged cheese"]}"#
        _ = parser.feed(line: "event: notes")
        _ = parser.feed(line: "data: \(json)")
        let result = parser.feed(line: "")
        guard case .notes(let payload) = result else { XCTFail("expected .notes"); return }
        XCTAssertEqual(payload.wine_id, "abc")
        XCTAssertEqual(payload.tasting_note, "Rich and velvety.")
        XCTAssertEqual(payload.pairings, ["lamb", "duck", "aged cheese"])
    }

    func testNotesEventNullTastingNote() {
        var parser = SSEParser()
        let json = #"{"wine_id":"abc","tasting_note":null,"pairings":[]}"#
        _ = parser.feed(line: "event: notes")
        _ = parser.feed(line: "data: \(json)")
        let result = parser.feed(line: "")
        guard case .notes(let payload) = result else { XCTFail("expected .notes"); return }
        XCTAssertNil(payload.tasting_note)
        XCTAssertEqual(payload.pairings, [])
    }

    // MARK: - error event

    func testErrorEvent() {
        var parser = SSEParser()
        let json = #"{"code":"OLLAMA_DOWN","wine_index":2,"message":"Ollama not reachable"}"#
        _ = parser.feed(line: "event: error")
        _ = parser.feed(line: "data: \(json)")
        let result = parser.feed(line: "")
        guard case .error(let payload) = result else { XCTFail("expected .error"); return }
        XCTAssertEqual(payload.code, "OLLAMA_DOWN")
        XCTAssertEqual(payload.wine_index, 2)
        XCTAssertEqual(payload.message, "Ollama not reachable")
    }

    func testErrorEventNoWineIndex() {
        var parser = SSEParser()
        let json = #"{"code":"SCANNER_BUSY","message":"Scan in progress"}"#
        _ = parser.feed(line: "event: error")
        _ = parser.feed(line: "data: \(json)")
        let result = parser.feed(line: "")
        guard case .error(let payload) = result else { XCTFail("expected .error"); return }
        XCTAssertNil(payload.wine_index)
    }

    // MARK: - complete event

    func testCompleteEvent() {
        var parser = SSEParser()
        let json = #"{"wine_count":12,"cache_hits":4,"scan_id":"scan-abc-123"}"#
        _ = parser.feed(line: "event: complete")
        _ = parser.feed(line: "data: \(json)")
        let result = parser.feed(line: "")
        guard case .complete(let payload) = result else { XCTFail("expected .complete"); return }
        XCTAssertEqual(payload.wine_count, 12)
        XCTAssertEqual(payload.cache_hits, 4)
        XCTAssertEqual(payload.scan_id, "scan-abc-123")
    }

    // MARK: - edge cases

    func testEmptyDataLineReturnsNil() {
        var parser = SSEParser()
        _ = parser.feed(line: "event: wine")
        let result = parser.feed(line: "")
        XCTAssertNil(result, "blank-line flush with no data should return nil")
    }

    func testUnknownEventTypeReturnsNil() {
        var parser = SSEParser()
        _ = parser.feed(line: "event: retry")
        _ = parser.feed(line: "data: 5000")
        let result = parser.feed(line: "")
        XCTAssertNil(result, "unknown event type should return nil")
    }

    func testDataBeforeEventUsesDefaultMessageType() {
        var parser = SSEParser()
        _ = parser.feed(line: #"data: {"name":"Test","confidence":0.8}"#)
        let result = parser.feed(line: "")
        XCTAssertNil(result, "default 'message' event type is unknown and should return nil")
    }

    func testMalformedJsonReturnsParseError() {
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

    func testMultipleEventsSequential() {
        var parser = SSEParser()

        // First event
        _ = parser.feed(line: "event: wine")
        _ = parser.feed(line: #"data: {"name":"Margaux","confidence":0.9}"#)
        let first = parser.feed(line: "")
        guard case .wine(let w) = first else { XCTFail("expected first event to be .wine"); return }
        XCTAssertEqual(w.name, "Margaux")

        // Second event (different type)
        _ = parser.feed(line: "event: complete")
        _ = parser.feed(line: #"data: {"wine_count":1,"cache_hits":0,"scan_id":"s1"}"#)
        let second = parser.feed(line: "")
        guard case .complete(let c) = second else { XCTFail("expected second event to be .complete"); return }
        XCTAssertEqual(c.wine_count, 1)
    }

    func testSSEParserChunkedPartialLine() {
        // SSE spec allows data: and event: fields in any order within a block.
        // Verify the parser accumulates them correctly regardless of order.
        var parser = SSEParser()
        XCTAssertNil(parser.feed(line: #"data: {"name":"Margaux","confidence":0.9}"#))
        XCTAssertNil(parser.feed(line: "event: wine"))
        let result = parser.feed(line: "")
        guard case .wine(let wine) = result else {
            XCTFail(
                "expected .wine when data: precedes event: in the same SSE block; got \(String(describing: result))")
            return
        }
        XCTAssertEqual(wine.name, "Margaux")
    }

    func testSSEParserMultilineData() {
        // SSE spec §9.2.6: multiple data: fields are concatenated with U+000A (LF).
        // The clobbering bug (data = value instead of data += "\n" + value) would
        // leave only the second fragment, causing JSON decode to fail → returns nil.
        var parser = SSEParser()
        XCTAssertNil(parser.feed(line: "event: wine"))
        XCTAssertNil(parser.feed(line: #"data: {"name":"Margaux","#))
        XCTAssertNil(parser.feed(line: #"data: "confidence":0.9}"#))
        let result = parser.feed(line: "")
        guard case .wine(let wine) = result else {
            XCTFail(
                "multi-line data: fields must concatenate with \\n per SSE spec; got \(String(describing: result))"
            )
            return
        }
        XCTAssertEqual(wine.name, "Margaux")
    }
}
