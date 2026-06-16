#!/usr/bin/env swift
// validate-brave-hitrate.swift
//
// Run before wiring BraveSearchClient into the app.
// Tests 20 wines spanning common, regional, and obscure bottles and reports:
//   - What % of queries return any image result
//   - What % pass the portrait ratio filter (h/w > 1.2)
//   - Per-query trace of HTTP status, result counts, and failure reason
//
// Usage:
//   BRAVE_API_KEY=your_key swift Scripts/validate-brave-hitrate.swift
//   BRAVE_API_KEY=your_key swift Scripts/validate-brave-hitrate.swift --verbose

import Foundation

// MARK: - CLI flags

let verbose = CommandLine.arguments.contains("--verbose")

// MARK: - Test wines

let testWines: [(name: String, vintage: String, tier: String)] = [
    // Common / Widely Available
    ("Château Margaux", "2018", "flagship"),
    ("Opus One", "2019", "flagship"),
    ("Penfolds Grange", "2018", "flagship"),
    ("Screaming Eagle", "2019", "flagship"),
    ("Domaine de la Romanée-Conti", "2017", "flagship"),
    // Regional / Mid-range
    ("Trimbach Riesling Clos Sainte Hune", "2018", "regional"),
    ("Donnhoff Oberhauser Brücke Auslese", "2020", "regional"),
    ("Alión", "2018", "regional"),
    ("Alvaro Palacios L'Ermita", "2019", "regional"),
    ("Cos d'Estournel", "2017", "regional"),
    ("Ridge Monte Bello", "2019", "regional"),
    ("Au Bon Climat Pinot Noir", "2020", "regional"),
    // Obscure / Restaurant-specific
    ("Domaine Weinbach Cuvée Théo", "2019", "obscure"),
    ("Clos Rougeard Saumur-Champigny", "2018", "obscure"),
    ("Movia Lunar", "2020", "obscure"),
    ("Radikon Ribolla Gialla", "2015", "obscure"),
    ("Gravner Anfora Bianco Breg", "2011", "obscure"),
    ("Elisabetta Foradori Granato", "2018", "obscure"),
    ("Weingut Keller G-Max Riesling", "2019", "obscure"),
    ("Sine Qua Non Poker Face", "2016", "obscure"),
]

// MARK: - Brave API structures

struct BraveResponse: Decodable {
    let results: [BraveResult]?
    struct BraveResult: Decodable {
        let thumbnail: Thumbnail?
        let properties: Properties?
        let url: String?
        struct Thumbnail: Decodable { let src: String? }
        struct Properties: Decodable { let height: Int?; let width: Int? }
    }
}

// MARK: - Result model

enum FailureReason: CustomStringConvertible {
    case networkError(String)
    case httpError(Int, String)
    case decodeError(String)
    case noResults
    case noDimensionData(rawCount: Int)
    case portraitFilterFailed(ratios: [Double])

    var description: String {
        switch self {
        case .networkError(let msg): return "network error: \(msg)"
        case .httpError(let code, let body): return "HTTP \(code): \(body.prefix(120))"
        case .decodeError(let msg): return "JSON decode failed: \(msg)"
        case .noResults: return "Brave returned 0 results"
        case .noDimensionData(let n): return "\(n) result(s) returned, but none have h/w dimension data"
        case .portraitFilterFailed(let rs):
            let formatted = rs.map { String(format: "%.2f", $0) }.joined(separator: ", ")
            return "portrait filter failed — ratios: [\(formatted)] (need h/w > 1.2)"
        }
    }
}

struct QueryResult {
    let wine: String
    let tier: String
    let query: String
    let httpStatus: Int?
    // Breakdown of what Brave actually returned
    let rawResultCount: Int  // total results in response
    let withDimensionsCount: Int  // results that have h/w data
    let allRatios: [Double]  // h/w for every result that has dimensions
    let portraitURL: String?  // first URL passing the portrait filter
    let failureReason: FailureReason?

    var isPortrait: Bool { portraitURL != nil }
    var hasAnyResult: Bool { rawResultCount > 0 }
    var hasDimensionData: Bool { withDimensionsCount > 0 }
}

// MARK: - State

// Sequential execution (1 req/sec) means no concurrent access — no locks needed.
var results: [QueryResult] = []

func log(_ line: String) { print(line) }

// MARK: - Guard on API key

guard let apiKey = ProcessInfo.processInfo.environment["BRAVE_API_KEY"], !apiKey.isEmpty else {
    print("ERROR: BRAVE_API_KEY not set")
    print("Usage: BRAVE_API_KEY=your_key swift Scripts/validate-brave-hitrate.swift")
    exit(1)
}

// MARK: - Fire requests

let searchBase = "https://api.search.brave.com/res/v1/images/search"

// Brave Free plan: 1 query/second. We fire sequentially with a 1.1s gap.
let rateLimitDelay: TimeInterval = 1.1

print("Sending \(testWines.count) queries to Brave Image Search (1 req/sec)…\n")

for (idx, wine) in testWines.enumerated() {
    if idx > 0 { Thread.sleep(forTimeInterval: rateLimitDelay) }

    let query = "\(wine.name) \(wine.vintage) wine bottle"
    let n = idx + 1

    var components = URLComponents(string: searchBase)!
    components.queryItems = [
        URLQueryItem(name: "q", value: query),
        URLQueryItem(name: "count", value: "5"),
        URLQueryItem(name: "search_lang", value: "en"),
    ]
    guard let url = components.url else {
        results.append(
            QueryResult(
                wine: wine.name, tier: wine.tier, query: query,
                httpStatus: nil, rawResultCount: 0, withDimensionsCount: 0,
                allRatios: [], portraitURL: nil,
                failureReason: .networkError("could not build URL")
            ))
        continue
    }

    var request = URLRequest(url: url)
    request.setValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.timeoutInterval = 15

    let requestDone = DispatchSemaphore(value: 0)

    URLSession.shared.dataTask(with: request) { data, response, error in
        defer { requestDone.signal() }

        let httpResponse = response as? HTTPURLResponse
        let statusCode = httpResponse?.statusCode

        // — Network error
        if let error {
            let result = QueryResult(
                wine: wine.name, tier: wine.tier, query: query,
                httpStatus: nil, rawResultCount: 0, withDimensionsCount: 0,
                allRatios: [], portraitURL: nil,
                failureReason: .networkError(error.localizedDescription)
            )
            results.append(result)
            log("[\(n)/\(testWines.count)] ✗ \(wine.name) — \(result.failureReason!)")
            return
        }

        let rawBody = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""

        // — Non-200 HTTP
        guard let statusCode, statusCode == 200, let data else {
            let snippet = rawBody.isEmpty ? "(empty body)" : String(rawBody.prefix(200))
            let result = QueryResult(
                wine: wine.name, tier: wine.tier, query: query,
                httpStatus: statusCode, rawResultCount: 0, withDimensionsCount: 0,
                allRatios: [], portraitURL: nil,
                failureReason: .httpError(statusCode ?? -1, snippet)
            )
            results.append(result)
            log("[\(n)/\(testWines.count)] ✗ \(wine.name) — HTTP \(statusCode ?? -1)")
            if verbose { log("    body: \(snippet)") }
            return
        }

        // — JSON decode
        guard let resp = try? JSONDecoder().decode(BraveResponse.self, from: data) else {
            let snippet = String(rawBody.prefix(300))
            let result = QueryResult(
                wine: wine.name, tier: wine.tier, query: query,
                httpStatus: 200, rawResultCount: 0, withDimensionsCount: 0,
                allRatios: [], portraitURL: nil,
                failureReason: .decodeError(snippet)
            )
            results.append(result)
            log("[\(n)/\(testWines.count)] ✗ \(wine.name) — JSON decode failed")
            log("    raw: \(snippet)")
            return
        }

        let rawResults = resp.results ?? []
        let rawCount = rawResults.count

        // — No results at all
        guard rawCount > 0 else {
            let result = QueryResult(
                wine: wine.name, tier: wine.tier, query: query,
                httpStatus: 200, rawResultCount: 0, withDimensionsCount: 0,
                allRatios: [], portraitURL: nil,
                failureReason: .noResults
            )
            results.append(result)
            log("[\(n)/\(testWines.count)] ✗ \(wine.name) — 0 results from Brave")
            return
        }

        // Compute h/w for every result that has dimension data
        let withDims = rawResults.compactMap { r -> (BraveResponse.BraveResult, Double)? in
            guard let h = r.properties?.height, let w = r.properties?.width, w > 0 else { return nil }
            return (r, Double(h) / Double(w))
        }
        let allRatios = withDims.map(\.1)

        // — Results exist but none have dimension data
        guard !withDims.isEmpty else {
            let result = QueryResult(
                wine: wine.name, tier: wine.tier, query: query,
                httpStatus: 200, rawResultCount: rawCount, withDimensionsCount: 0,
                allRatios: [], portraitURL: nil,
                failureReason: .noDimensionData(rawCount: rawCount)
            )
            results.append(result)
            log("[\(n)/\(testWines.count)] ~ \(wine.name) — \(rawCount) result(s), 0 with h/w data")
            if verbose {
                for (i, r) in rawResults.enumerated() {
                    log("    [\(i+1)] url=\(r.url ?? "nil") thumb=\(r.thumbnail?.src ?? "nil")")
                }
            }
            return
        }

        // Find first result passing portrait filter
        let portrait = withDims.first(where: { $0.1 > 1.2 })

        // — Results + dimensions, but portrait filter rejects all
        guard let (portraitResult, portraitRatio) = portrait else {
            let result = QueryResult(
                wine: wine.name, tier: wine.tier, query: query,
                httpStatus: 200, rawResultCount: rawCount, withDimensionsCount: withDims.count,
                allRatios: allRatios, portraitURL: nil,
                failureReason: .portraitFilterFailed(ratios: allRatios)
            )
            results.append(result)
            let ratioStr = allRatios.map { String(format: "%.2f", $0) }.joined(separator: ", ")
            log(
                "[\(n)/\(testWines.count)] ~ \(wine.name) — \(rawCount) results, ratios: [\(ratioStr)] — portrait filter rejected all"
            )
            return
        }

        // — Success
        let result = QueryResult(
            wine: wine.name, tier: wine.tier, query: query,
            httpStatus: 200, rawResultCount: rawCount, withDimensionsCount: withDims.count,
            allRatios: allRatios, portraitURL: portraitResult.thumbnail?.src,
            failureReason: nil
        )
        results.append(result)
        let ratioStr = allRatios.map { String(format: "%.2f", $0) }.joined(separator: ", ")
        log(
            "[\(n)/\(testWines.count)] ✓ \(wine.name) — \(rawCount) results, ratios: [\(ratioStr)], portrait h/w=\(String(format: "%.2f", portraitRatio))"
        )
        if verbose, let thumbURL = portraitResult.thumbnail?.src {
            log("    url: \(thumbURL)")
        }
    }.resume()
    requestDone.wait()
}

// MARK: - Summary report

print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("BRAVE IMAGE SEARCH — VALIDATION REPORT")
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

// Per-tier breakdown
for tier in ["flagship", "regional", "obscure"] {
    let group = results.filter { $0.tier == tier }.sorted { $0.wine < $1.wine }
    let portrait = group.filter { $0.isPortrait }.count
    let anyResult = group.filter { $0.hasAnyResult }.count
    let hasDims = group.filter { $0.hasDimensionData }.count
    print(
        "\n[\(tier.uppercased())] \(portrait)/\(group.count) portrait | \(hasDims)/\(group.count) have dimensions | \(anyResult)/\(group.count) any result"
    )

    for r in group {
        let marker = r.isPortrait ? "✓" : r.failureReason == nil ? "?" : "✗"
        let name = r.wine.prefix(40).padding(toLength: 40, withPad: " ", startingAt: 0)
        if let reason = r.failureReason {
            print("  \(marker) \(name) → \(reason)")
        } else {
            let ratioStr = r.allRatios.map { String(format: "%.2f", $0) }.joined(separator: ", ")
            print("  \(marker) \(name) → ratios: [\(ratioStr)]")
        }
    }
}

// Failure breakdown by category
let categories: [(String, (QueryResult) -> Bool)] = [
    (
        "network error",
        {
            if case .networkError = $0.failureReason { return true }; return false
        }
    ),
    (
        "HTTP error",
        {
            if case .httpError = $0.failureReason { return true }; return false
        }
    ),
    (
        "JSON decode error",
        {
            if case .decodeError = $0.failureReason { return true }; return false
        }
    ),
    (
        "0 results from Brave",
        {
            if case .noResults = $0.failureReason { return true }; return false
        }
    ),
    (
        "no dimension data",
        {
            if case .noDimensionData = $0.failureReason { return true }; return false
        }
    ),
    (
        "portrait filter fail",
        {
            if case .portraitFilterFailed = $0.failureReason { return true }; return false
        }
    ),
]

let failures = results.filter { $0.failureReason != nil }
if !failures.isEmpty {
    print("\n─ Failure breakdown (\(failures.count) total) ─")
    for (label, check) in categories {
        let count = results.filter(check).count
        if count > 0 { print("  \(count)× \(label)") }
    }
}

// Portrait filter analysis: of all results that had ratios, what was the distribution?
let allRatiosFlat = results.flatMap { $0.allRatios }
if !allRatiosFlat.isEmpty {
    let passing = allRatiosFlat.filter { $0 > 1.2 }.count
    let totalR = allRatiosFlat.count
    let avg = allRatiosFlat.reduce(0, +) / Double(totalR)
    let maxR = allRatiosFlat.max()!
    let minR = allRatiosFlat.min()!
    print("\n─ Ratio distribution across \(totalR) images with dimension data ─")
    print("  passing portrait filter (>1.2): \(passing)/\(totalR) (\(Int(Double(passing)/Double(totalR)*100))%)")
    print(
        "  avg h/w: \(String(format: "%.2f", avg))  min: \(String(format: "%.2f", minR))  max: \(String(format: "%.2f", maxR))"
    )
}

// Totals
let totalPortrait = results.filter { $0.isPortrait }.count
let totalAny = results.filter { $0.hasAnyResult }.count
let totalDims = results.filter { $0.hasDimensionData }.count
let total = results.count

print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("TOTALS (\(total) queries)")
print(
    "  \(totalPortrait)/\(total) (\(Int(Double(totalPortrait)/Double(total)*100))%) — portrait bottle image found ← primary metric"
)
print("  \(totalDims)/\(total) (\(Int(Double(totalDims)/Double(total)*100))%) — results with dimension data")
print("  \(totalAny)/\(total) (\(Int(Double(totalAny)/Double(total)*100))%) — any result returned by Brave")
print("TARGET: ≥70% portrait for v1 viability")

if Double(totalPortrait) / Double(total) >= 0.7 {
    print("VERDICT: ✓ PASS — Brave image search viable as primary source")
} else if Double(totalDims) / Double(total) >= 0.7 {
    print("VERDICT: ~ MARGINAL — Dimensions present but portrait filter too strict; try h/w > 1.0")
} else if Double(totalAny) / Double(total) >= 0.7 {
    print("VERDICT: ~ MARGINAL — Results returned but dimension data absent; check Brave API tier/params")
} else {
    print("VERDICT: ✗ FAIL — Brave coverage insufficient; implement DALL-E 3 fallback as Plan B")
}
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
