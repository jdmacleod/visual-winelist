import Foundation

struct WineObject: Codable, Identifiable, Equatable, Sendable {
    let name: String
    let producer: String?
    let vintage: String?
    let variety: String?
    let appellation: String?
    let price: String?
    let description: String?
    let listSection: String?
    let rawText: String?
    let confidence: Double

    var id: String { "\(name.lowercased())-\(vintage ?? "nv")" }

    static func == (lhs: WineObject, rhs: WineObject) -> Bool {
        lhs.name.lowercased() == rhs.name.lowercased() && lhs.vintage?.lowercased() == rhs.vintage?.lowercased()
    }
}
