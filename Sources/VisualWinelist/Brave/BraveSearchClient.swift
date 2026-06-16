import Foundation

struct BraveSearchClient: Sendable {
    private let apiKey: String
    private let rateLimiter: RateLimiter
    private static let searchURL = URL(string: "https://api.search.brave.com/res/v1/images/search")!

    init(apiKey: String) {
        self.apiKey = apiKey
        self.rateLimiter = RateLimiter(requestsPerSecond: 1)
    }

    // Returns image data for the wine, or nil if no usable bottle image is found.
    func fetchBottleImage(for wine: WineObject) async -> Data? {
        await rateLimiter.wait()
        // Use producer (more recognizable than wine name) + variety + vintage for specificity.
        let producer = wine.producer ?? wine.name
        let variety = wine.variety.map { " \($0)" } ?? ""
        let vintage = wine.vintage.map { " \($0)" } ?? ""
        let query = "\(producer)\(variety)\(vintage) wine bottle"
        print("[Brave] query='\(query)'")

        var components = URLComponents(url: Self.searchURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            // Pull more than the old count=5: with only 5 raw results, a hard portrait
            // filter can easily zero out every candidate even though Brave's own UI
            // (which surfaces dozens of results) clearly has usable bottle photos.
            URLQueryItem(name: "count", value: "20"),
            URLQueryItem(name: "search_lang", value: "en"),
        ]
        guard let url = components.url else {
            print("[Brave] could not build request URL for '\(query)'")
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            print("[Brave] search request errored for '\(query)': \(error.localizedDescription)")
            return nil
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            print("[Brave] search request returned a non-HTTP response for '\(query)'")
            return nil
        }
        guard httpResponse.statusCode == 200 else {
            print("[Brave] search request failed for '\(query)': HTTP \(httpResponse.statusCode)")
            return nil
        }
        guard let braveResponse = try? JSONDecoder().decode(BraveImageResponse.self, from: data) else {
            let preview = String(data: data, encoding: .utf8).map { String($0.prefix(200)) } ?? "(binary)"
            print("[Brave] could not decode search response for '\(query)': \(preview)")
            return nil
        }

        let allResults = braveResponse.results ?? []
        if allResults.isEmpty {
            print("[Brave] Brave returned 0 results for '\(query)' — query may be too specific or misspelled")
            return nil
        }

        let portraitCount = allResults.filter { isPortrait($0) }.count
        print("[Brave] \(allResults.count) results, \(portraitCount) portrait candidates")
        for (idx, result) in allResults.enumerated() {
            let w = result.properties?.width
            let h = result.properties?.height
            let ratio: Double? = (w.flatMap { ww in h.map { hh in (ww, hh) } }).map { ww, hh in
                ww > 0 ? Double(hh) / Double(ww) : 0
            }
            let dims = "\(w.map(String.init) ?? "?")x\(h.map(String.init) ?? "?")"
            let ratioStr = ratio.map { String(format: "%.2f", $0) } ?? "n/a"
            let thumb = result.thumbnail?.src ?? "(no thumbnail)"
            print("[Brave]   [\(idx)] dims=\(dims) ratio=\(ratioStr) portrait=\(isPortrait(result)) thumb=\(thumb)")
        }

        // Rank by "how portrait-shaped" each result is (closer to a bottle's aspect
        // ratio first), but DON'T hard-drop the rest — if every portrait candidate
        // fails to download, fall back to the next-best shape instead of giving up.
        let ranked = allResults.sorted { portraitScore($0) > portraitScore($1) }

        for (idx, candidate) in ranked.prefix(8).enumerated() {
            guard let src = candidate.thumbnail?.src, let imageURL = URL(string: src) else {
                print("[Brave]   candidate \(idx): missing/invalid thumbnail URL, skipping")
                continue
            }
            switch await downloadImage(from: imageURL) {
            case .success(let imageData):
                print("[Brave] selected: \(src) (\(imageData.count) bytes, attempt \(idx + 1))")
                return imageData
            case .failure(let reason):
                print("[Brave]   candidate \(idx) download failed (\(reason)): \(src)")
            }
        }
        print(
            "[Brave] no usable image for '\(query)' — \(allResults.count) results, \(portraitCount) portrait, all \(min(ranked.count, 8)) attempted downloads failed"
        )
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

    // Continuous aspect-ratio score used for ranking, not filtering — a result with
    // no dimensions or a non-portrait shape still gets tried, just lower in the order.
    private func portraitScore(_ result: BraveImageResult) -> Double {
        guard let h = result.properties?.height, let w = result.properties?.width, w > 0 else {
            return -1
        }
        return Double(h) / Double(w)
    }

    private enum DownloadFailure: Error, CustomStringConvertible {
        case requestError(String)
        case httpStatus(Int)
        case empty

        var description: String {
            switch self {
            case .requestError(let msg): return "network error: \(msg)"
            case .httpStatus(let code): return "HTTP \(code)"
            case .empty: return "empty body"
            }
        }
    }

    private func downloadImage(from url: URL) async -> Result<Data, DownloadFailure> {
        var request = URLRequest(url: url)
        // Some image hosts (retailer CDNs in particular) reject hotlinked requests
        // with no User-Agent — set one so those candidates aren't silently dropped.
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.timeoutInterval = 8

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.requestError("non-HTTP response"))
            }
            guard httpResponse.statusCode == 200 else {
                return .failure(.httpStatus(httpResponse.statusCode))
            }
            guard !data.isEmpty else {
                return .failure(.empty)
            }
            return .success(data)
        } catch {
            return .failure(.requestError(error.localizedDescription))
        }
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
