import Foundation

struct BraveImageResponse: Decodable {
    let results: [BraveImageResult]?
}

struct BraveImageResult: Decodable {
    let thumbnail: Thumbnail?
    let properties: Properties?

    struct Thumbnail: Decodable {
        let src: String?
    }

    struct Properties: Decodable {
        let url: String?
        let height: Int?
        let width: Int?
    }
}
