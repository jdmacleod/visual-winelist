import Foundation

struct WineObject: Codable, Identifiable, Equatable, Sendable {
    let name: String
    let producer: String?
    let vintage: String?
    let variety: String?
    let appellation: String?
    let price: String?
    let description: String?  // description from the wine list itself
    let listSection: String?
    let rawText: String?
    let confidence: Double
    var wineId: String?        // set by backend (wine_id field)
    var tastingNote: String?   // set from event: notes (sommelier)
    var pairings: [String]     // set from event: notes (sommelier)

    enum CodingKeys: String, CodingKey {
        case name, producer, vintage, variety, appellation, price, description
        case listSection, rawText, confidence
        case wineId = "wine_id"
        case tastingNote = "tasting_note"
        case pairings
    }

    init(
        name: String,
        producer: String? = nil,
        vintage: String? = nil,
        variety: String? = nil,
        appellation: String? = nil,
        price: String? = nil,
        description: String? = nil,
        listSection: String? = nil,
        rawText: String? = nil,
        confidence: Double,
        wineId: String? = nil,
        tastingNote: String? = nil,
        pairings: [String] = []
    ) {
        self.name = name
        self.producer = producer
        self.vintage = vintage
        self.variety = variety
        self.appellation = appellation
        self.price = price
        self.description = description
        self.listSection = listSection
        self.rawText = rawText
        self.confidence = confidence
        self.wineId = wineId
        self.tastingNote = tastingNote
        self.pairings = pairings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        producer = try c.decodeIfPresent(String.self, forKey: .producer)
        vintage = try c.decodeIfPresent(String.self, forKey: .vintage)
        variety = try c.decodeIfPresent(String.self, forKey: .variety)
        appellation = try c.decodeIfPresent(String.self, forKey: .appellation)
        price = try c.decodeIfPresent(String.self, forKey: .price)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        listSection = try c.decodeIfPresent(String.self, forKey: .listSection)
        rawText = try c.decodeIfPresent(String.self, forKey: .rawText)
        confidence = try c.decode(Double.self, forKey: .confidence)
        wineId = try c.decodeIfPresent(String.self, forKey: .wineId)
        tastingNote = try c.decodeIfPresent(String.self, forKey: .tastingNote)
        pairings = (try? c.decode([String].self, forKey: .pairings)) ?? []
    }

    var id: String { wineId ?? "\(name.lowercased())-\(vintage ?? "nv")" }

    static func == (lhs: WineObject, rhs: WineObject) -> Bool {
        if let lid = lhs.wineId, let rid = rhs.wineId { return lid == rid }
        return lhs.name.lowercased() == rhs.name.lowercased()
            && lhs.vintage?.lowercased() == rhs.vintage?.lowercased()
    }
}
