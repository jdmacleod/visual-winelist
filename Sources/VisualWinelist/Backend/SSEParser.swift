import Foundation

enum SSEEvent: Sendable {
    case wine(WineObject)
    case image(ImageSSEPayload)
    case notes(NotesSSEPayload)
    case error(ErrorSSEPayload)
    case complete(CompleteSSEPayload)
    case ping
    case parseError(String)
}

/// Stateful line-by-line SSE parser.
///
/// Feed one line at a time with `feed(line:)`. Returns a dispatch event when
/// a blank line is encountered (SSE event boundary), or `.ping` for comment lines.
/// All other lines (event:, data:) are buffered internally.
///
/// This is the D7 isolatable unit — all logic is pure struct methods, no networking.
struct SSEParser {
    private var eventType: String = "message"
    private var data: String = ""

    mutating func feed(line: String) -> SSEEvent? {
        if line.hasPrefix(":") {
            return .ping
        }
        if line.isEmpty {
            defer { eventType = "message"; data = "" }
            return dispatch()
        }
        if line.hasPrefix("event: ") {
            eventType = String(line.dropFirst(7))
            return nil
        }
        if line.hasPrefix("data: ") {
            let value = String(line.dropFirst(6))
            data = data.isEmpty ? value : data + "\n" + value
            return nil
        }
        return nil
    }

    private func dispatch() -> SSEEvent? {
        guard !data.isEmpty, let jsonData = data.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        do {
            switch eventType {
            case "wine": return .wine(try decoder.decode(WineObject.self, from: jsonData))
            case "image": return .image(try decoder.decode(ImageSSEPayload.self, from: jsonData))
            case "notes": return .notes(try decoder.decode(NotesSSEPayload.self, from: jsonData))
            case "error": return .error(try decoder.decode(ErrorSSEPayload.self, from: jsonData))
            case "complete": return .complete(try decoder.decode(CompleteSSEPayload.self, from: jsonData))
            default: return nil
            }
        } catch {
            return .parseError("\(eventType): \(error)")
        }
    }
}
