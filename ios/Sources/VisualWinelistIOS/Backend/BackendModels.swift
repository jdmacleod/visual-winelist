// swiftlint:disable identifier_name
import Foundation

struct ImageSSEPayload: Decodable, Sendable {
    let wine_id: String
    let url: String
    let placeholder: Bool
}

struct NotesSSEPayload: Decodable, Sendable {
    let wine_id: String
    let tasting_note: String?
    let pairings: [String]
}

struct ErrorSSEPayload: Decodable, Sendable {
    let code: String
    let wine_index: Int?
    let message: String
}

struct CompleteSSEPayload: Decodable, Sendable {
    let wine_count: Int
    let cache_hits: Int
    let scan_id: String
}

struct HealthResponse: Decodable, Sendable {
    let status: String
    let ollama: Bool
    let brave_key: Bool

    var isOK: Bool { status == "ok" }
}
