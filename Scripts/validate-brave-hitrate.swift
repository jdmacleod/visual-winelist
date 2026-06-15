#!/usr/bin/env swift
// validate-brave-hitrate.swift
//
// Run before wiring BraveSearchClient into the app.
// Tests 20 wines spanning common, regional, and obscure bottles and reports:
//   - What % of queries return any image result
//   - What % pass the portrait ratio filter (h/w > 1.2)
//   - Sample URLs for manual inspection
//
// Usage:
//   BRAVE_API_KEY=your_key swift Scripts/validate-brave-hitrate.swift

import Foundation

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
        struct Thumbnail: Decodable { let src: String? }
        struct Properties: Decodable { let height: Int?; let width: Int? }
    }
}

// MARK: - Main

guard let apiKey = ProcessInfo.processInfo.environment["BRAVE_API_KEY"], !apiKey.isEmpty else {
    print("ERROR: BRAVE_API_KEY not set")
    print("Usage: BRAVE_API_KEY=your_key swift Scripts/validate-brave-hitrate.swift")
    exit(1)
}

struct Result {
    let wine: String
    let tier: String
    let hasResult: Bool
    let isPortrait: Bool
    let url: String?
    let hw: Double?
}

var results: [Result] = []
let semaphore = DispatchSemaphore(value: 0)
var pending = testWines.count

func isPortrait(h: Int?, w: Int?) -> Bool {
    guard let h, let w, w > 0 else { return false }
    return Double(h) / Double(w) > 1.2
}

for wine in testWines {
    let query = "\(wine.name) \(wine.vintage) wine bottle"
    var components = URLComponents(string: "https://api.search.brave.com/res/v1/images/search")!
    components.queryItems = [
        URLQueryItem(name: "q", value: query),
        URLQueryItem(name: "count", value: "5")
    ]
    guard let url = components.url else { continue }
    var request = URLRequest(url: url)
    request.setValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.timeoutInterval = 10

    URLSession.shared.dataTask(with: request) { data, response, error in
        defer {
            pending -= 1
            if pending == 0 { semaphore.signal() }
        }

        guard let data, error == nil,
              (response as? HTTPURLResponse)?.statusCode == 200,
              let resp = try? JSONDecoder().decode(BraveResponse.self, from: data)
        else {
            results.append(Result(wine: wine.name, tier: wine.tier, hasResult: false, isPortrait: false, url: nil, hw: nil))
            return
        }

        // Find first portrait candidate
        let candidates = (resp.results ?? []).compactMap { r -> (BraveResponse.BraveResult, Double)? in
            guard let h = r.properties?.height, let w = r.properties?.width, w > 0 else { return nil }
            return (r, Double(h) / Double(w))
        }

        let hasAny = !candidates.isEmpty
        let portrait = candidates.first(where: { $0.1 > 1.2 })

        results.append(Result(
            wine: wine.name,
            tier: wine.tier,
            hasResult: hasAny,
            isPortrait: portrait != nil,
            url: portrait?.0.thumbnail?.src ?? candidates.first?.0.thumbnail?.src,
            hw: portrait?.1 ?? candidates.first?.1
        ))
    }.resume()
}

semaphore.wait()

// MARK: - Report

print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("BRAVE IMAGE SEARCH — VALIDATION REPORT")
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

let sorted = results.sorted { $0.tier < $1.tier }
for tier in ["flagship", "regional", "obscure"] {
    let group = sorted.filter { $0.tier == tier }
    let anyResults = group.filter { $0.hasResult }.count
    let portrait = group.filter { $0.isPortrait }.count
    print("\n[\(tier.uppercased())] \(portrait)/\(group.count) portrait | \(anyResults)/\(group.count) any result")
    for r in group {
        let marker = r.isPortrait ? "✓" : r.hasResult ? "~" : "✗"
        let ratio = r.hw.map { String(format: "h/w=%.2f", $0) } ?? "no result"
        print("  \(marker) \(r.wine.prefix(40).padding(toLength: 40, withPad: " ", startingAt: 0)) \(ratio)")
    }
}

let totalPortrait = results.filter { $0.isPortrait }.count
let totalAny = results.filter { $0.hasResult }.count
let total = results.count

print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("TOTAL: \(totalPortrait)/\(total) portrait (\(Int(Double(totalPortrait)/Double(total)*100))%) | \(totalAny)/\(total) any result (\(Int(Double(totalAny)/Double(total)*100))%)")
print("TARGET: ≥70% portrait for v1 viability")

if Double(totalPortrait) / Double(total) >= 0.7 {
    print("VERDICT: ✓ PASS — Brave image search is viable as primary source")
} else if Double(totalAny) / Double(total) >= 0.7 {
    print("VERDICT: ~ MARGINAL — Many results but poor portrait ratio; consider looser filter or additional image processing")
} else {
    print("VERDICT: ✗ FAIL — Brave coverage insufficient; implement DALL-E 3 fallback as Plan B")
}
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
