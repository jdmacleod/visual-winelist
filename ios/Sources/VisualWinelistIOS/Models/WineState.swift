import Foundation

enum WineState: Identifiable, Sendable {
    case extracting(WineObject)
    case fetchingImage(WineObject)
    case ready(WineObject, Data)
    case placeholder(WineObject)

    var id: String { wine.id }

    var wine: WineObject {
        switch self {
        case .extracting(let w), .fetchingImage(let w), .placeholder(let w): return w
        case .ready(let w, _): return w
        }
    }

    var imageData: Data? {
        guard case .ready(_, let data) = self else { return nil }
        return data
    }

    var isLoading: Bool {
        switch self {
        case .extracting, .fetchingImage: return true
        case .ready, .placeholder: return false
        }
    }

    var isLowConfidence: Bool { wine.confidence < 0.7 }

    func withUpdatedWine(_ wine: WineObject) -> WineState {
        switch self {
        case .extracting: return .extracting(wine)
        case .fetchingImage: return .fetchingImage(wine)
        case .ready(_, let data): return .ready(wine, data)
        case .placeholder: return .placeholder(wine)
        }
    }
}
