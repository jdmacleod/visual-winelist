import Foundation

enum SSEEvent: Sendable {
    case wine(WineObject)
    case image(ImageSSEPayload)
    case notes(NotesSSEPayload)
    case error(ErrorSSEPayload)
    case complete(CompleteSSEPayload)
    case ping
}

/// Stateful line-by-line SSE parser. Feed one line at a time; returns an event at blank-line boundaries.
struct SSEParser {
    private var eventType: String = "message"
    private var data: String = ""

    mutating func feed(line: String) -> SSEEvent? {
        if line.hasPrefix(":") { return .ping }
        if line.isEmpty {
            defer { eventType = "message"; data = "" }
            return dispatch()
        }
        if line.hasPrefix("event: ") { eventType = String(line.dropFirst(7)); return nil }
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
        switch eventType {
        case "wine":
            return (try? decoder.decode(WineObject.self, from: jsonData)).map { .wine($0) }
        case "image":
            return (try? decoder.decode(ImageSSEPayload.self, from: jsonData)).map { .image($0) }
        case "notes":
            return (try? decoder.decode(NotesSSEPayload.self, from: jsonData)).map { .notes($0) }
        case "error":
            return (try? decoder.decode(ErrorSSEPayload.self, from: jsonData)).map { .error($0) }
        case "complete":
            return (try? decoder.decode(CompleteSSEPayload.self, from: jsonData)).map { .complete($0) }
        default:
            return nil
        }
    }
}
