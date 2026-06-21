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
        if line.hasPrefix("data: ") { data = String(line.dropFirst(6)); return nil }
        return nil
    }

    private func dispatch() -> SSEEvent? {
        guard !data.isEmpty, let jsonData = data.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        switch eventType {
        case "wine":
            do {
                let wine = try decoder.decode(WineObject.self, from: jsonData)
                return .wine(wine)
            } catch {
                print("[DIAG] SSEParser: WineObject decode FAILED: \(error)\n  data=\(data.prefix(300))")
                return nil
            }
        case "image":
            do {
                return .image(try decoder.decode(ImageSSEPayload.self, from: jsonData))
            } catch {
                print("[DIAG] SSEParser: ImageSSEPayload decode FAILED: \(error)")
                return nil
            }
        case "notes":
            do {
                return .notes(try decoder.decode(NotesSSEPayload.self, from: jsonData))
            } catch {
                print("[DIAG] SSEParser: NotesSSEPayload decode FAILED: \(error)")
                return nil
            }
        case "error":
            do {
                return .error(try decoder.decode(ErrorSSEPayload.self, from: jsonData))
            } catch {
                print("[DIAG] SSEParser: ErrorSSEPayload decode FAILED: \(error)")
                return nil
            }
        case "complete":
            do {
                return .complete(try decoder.decode(CompleteSSEPayload.self, from: jsonData))
            } catch {
                print("[DIAG] SSEParser: CompleteSSEPayload decode FAILED: \(error)")
                return nil
            }
        default:
            print("[DIAG] SSEParser: unknown eventType=\(eventType)")
            return nil
        }
    }
}
