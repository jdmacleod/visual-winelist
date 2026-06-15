import Foundation

struct BraveSearchClient: Sendable {
    private let apiKey: String
    private let rateLimiter: RateLimiter
    private static let searchURL = URL(string: "https://api.search.brave.com/res/v1/images/search")!

    init(apiKey: String) {
        self.apiKey = apiKey
        self.rateLimiter = RateLimiter(requestsPerSecond: 1)
    }

    // Returns image data for the wine, or nil if no portrait bottle image is found.
    func fetchBottleImage(for wine: WineObject) async -> Data? {
        await rateLimiter.wait()
        let query = "\(wine.name) \(wine.vintage ?? "") wine bottle"

        var components = URLComponents(url: Self.searchURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "count", value: "5"),
            URLQueryItem(name: "search_lang", value: "en")
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let braveResponse = try? JSONDecoder().decode(BraveImageResponse.self, from: data)
        else { return nil }

        let candidates = (braveResponse.results ?? []).filter { isPortrait($0) }
        for candidate in candidates.prefix(3) {
            if let src = candidate.thumbnail?.src,
               let imageURL = URL(string: src),
               let imageData = await downloadImage(from: imageURL) {
                return imageData
            }
        }
        return nil
    }

    // Fetch images for multiple wines. Rate-limited to 1 req/sec by the shared RateLimiter.
    func fetchImages(for wines: [WineObject]) async -> [(WineObject, Data?)] {
        return await withTaskGroup(of: (WineObject, Data?).self) { group in
            for wine in wines {
                group.addTask {
                    let data = await self.fetchBottleImage(for: wine)
                    return (wine, data)
                }
            }
            var results: [(WineObject, Data?)] = []
            for await result in group { results.append(result) }
            return results
        }
    }

    // MARK: - Private

    private func isPortrait(_ result: BraveImageResult) -> Bool {
        guard let h = result.properties?.height, let w = result.properties?.width, w > 0 else {
            return false
        }
        return Double(h) / Double(w) > 1.2
    }

    private func downloadImage(from url: URL) async -> Data? {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              !data.isEmpty else { return nil }
        return data
    }
}

// Enforces a minimum interval between Brave API calls (Free plan: 1 req/sec).
actor RateLimiter {
    private let minimumInterval: TimeInterval
    private var lastFireDate: Date = .distantPast

    init(requestsPerSecond: Double) {
        self.minimumInterval = 1.0 / requestsPerSecond
    }

    func wait() async {
        let elapsed = Date().timeIntervalSince(lastFireDate)
        if elapsed < minimumInterval {
            let delay = UInt64((minimumInterval - elapsed) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
        }
        lastFireDate = Date()
    }
}
