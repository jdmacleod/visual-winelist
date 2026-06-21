// swiftlint:disable identifier_name
import Foundation

// Decoded from event: image
struct ImageSSEPayload: Decodable, Sendable {
    let wine_id: String
    let url: String
    let placeholder: Bool
}

// Decoded from event: notes
struct NotesSSEPayload: Decodable, Sendable {
    let wine_id: String
    let tasting_note: String?
    let pairings: [String]
}

// Decoded from event: error
struct ErrorSSEPayload: Decodable, Sendable {
    let code: String
    let wine_index: Int?
    let message: String
}

// Decoded from event: complete
struct CompleteSSEPayload: Decodable, Sendable {
    let wine_count: Int
    let cache_hits: Int
    let scan_id: String
}

// GET /health response
struct HealthResponse: Decodable, Sendable {
    let status: String
    let ollama: Bool
    let brave_key: Bool

    var isOK: Bool { status == "ok" }
}
