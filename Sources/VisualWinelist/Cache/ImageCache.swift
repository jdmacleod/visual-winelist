import Foundation
import CryptoKit

actor ImageCache {
    private let cacheDirectory: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        cacheDirectory = home
            .appendingPathComponent(".visual-winelist")
            .appendingPathComponent("image-cache")
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func fetch(for wine: WineObject) -> Data? {
        let path = cachePath(for: wine)
        return try? Data(contentsOf: path)
    }

    func store(_ data: Data, for wine: WineObject) {
        let path = cachePath(for: wine)
        try? data.write(to: path, options: .atomic)
    }

    func cacheKey(for wine: WineObject) -> String {
        let input = "\(wine.name.lowercased())\(wine.vintage ?? "")"
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func cachePath(for wine: WineObject) -> URL {
        cacheDirectory.appendingPathComponent(cacheKey(for: wine) + ".jpg")
    }
}
