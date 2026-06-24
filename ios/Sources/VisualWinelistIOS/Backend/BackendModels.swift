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

    private enum CodingKeys: String, CodingKey {
        case wine_id, tasting_note, pairings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        wine_id = try c.decode(String.self, forKey: .wine_id)
        tasting_note = try c.decodeIfPresent(String.self, forKey: .tasting_note)
        pairings = try c.decodeIfPresent([String].self, forKey: .pairings) ?? []
    }
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
    let receive_ms: Int?
    let first_wine_ms: Int?
    let ollama_ms: Int?
    let image_ms: Int?
    let sommelier_ms: Int?
    let total_ms: Int?
    let brave_search_ms: Int?
    let image_download_ms: Int?
}

struct HealthResponse: Decodable, Sendable {
    let status: String
    let ollama: Bool
    let brave_key: Bool

    var isOK: Bool { status == "ok" }
}
