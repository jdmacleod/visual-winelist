import Foundation

struct BraveSearchClient: Sendable {
    private let apiKey: String
    private static let searchURL = URL(string: "https://api.search.brave.com/res/v1/images/search")!
    private static let maxConcurrent = 5

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    // Returns image data for the wine, or nil if no portrait bottle image is found.
    func fetchBottleImage(for wine: WineObject) async -> Data? {
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

    // Fetch images for multiple wines with a sliding window of 5 concurrent requests.
    func fetchImages(for wines: [WineObject]) async -> [(WineObject, Data?)] {
        let semaphore = AsyncSemaphore(value: Self.maxConcurrent)
        return await withTaskGroup(of: (WineObject, Data?).self) { group in
            for wine in wines {
                group.addTask {
                    await semaphore.wait()
                    defer { Task { await semaphore.signal() } }
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

// Actor-based semaphore for capping concurrent URLSession tasks.
actor AsyncSemaphore {
    private var count: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) { self.count = value }

    func wait() async {
        if count > 0 {
            count -= 1
        } else {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
    }

    func signal() {
        if waiters.isEmpty {
            count += 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}
