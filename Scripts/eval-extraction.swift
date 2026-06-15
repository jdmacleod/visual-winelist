#!/usr/bin/env swift
// eval-extraction.swift
//
// Runs the Qwen3-VL wine extraction prompt against every image in resources/
// and reports per-photo and aggregate results.
//
// Usage:
//   swift Scripts/eval-extraction.swift
//   swift Scripts/eval-extraction.swift --verbose   # prints all extracted wines

import Foundation

// MARK: - CLI

let verbose = CommandLine.arguments.contains("--verbose")
let ollamaBase = "http://localhost:11434"
let model = "qwen3-vl:8b"

// MARK: - Prompt (mirror of WineExtractionPrompt.swift)

let extractionPrompt = """
You are analyzing a photo of a restaurant wine list. Extract every wine you can identify.

Output exactly one JSON object per line (JSONL format). No surrounding array. No markdown. No explanation.

Each line must be valid JSON with this exact schema:
{"name":"...","producer":"...","vintage":"...","variety":"...","appellation":"...","price":"...","description":"...","listSection":"...","rawText":"...","confidence":0.95}

Field rules:
- name: wine name as printed on the list (required)
- producer: winery or producer name; often the same as name (null if unclear)
- vintage: 4-digit year as a string, e.g. "2019" (null if not shown)
- variety: grape variety or blend, e.g. "Cabernet Sauvignon" (null if not shown)
- appellation: region or appellation, e.g. "Napa Valley, California" (null if not shown)
- price: price as printed including currency symbol, e.g. "$48" or "48" (null if not shown)
- description: any tasting notes or description from the list (null if none)
- listSection: the section header under which this wine appears, e.g. "Red Wines" or "By the Glass" (null if no section header)
- rawText: the complete original text for this wine entry as it appears on the list
- confidence: float from 0.0 to 1.0 — your certainty that name and vintage are correctly extracted. Use 0.9+ for clear text, 0.6-0.8 for partially legible text, below 0.6 for guesses.

Output ONLY JSON lines. One wine per line. No other text.
"""

// MARK: - Types

struct WineObject: Decodable {
    let name: String
    let producer: String?
    let vintage: String?
    let variety: String?
    let appellation: String?
    let price: String?
    let description: String?
    let listSection: String?
    let rawText: String?
    let confidence: Double?
}

struct PhotoResult {
    let filename: String
    let wines: [WineObject]
    let parseErrors: [(line: String, error: String)]
    let httpStatus: Int?
    let networkError: String?
    let rawLineCount: Int
    let durationSeconds: Double
}

// MARK: - Helpers

func imageData(for path: String) -> Data? {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
    return data
}

func mimeType(for path: String) -> String {
    switch (path as NSString).pathExtension.lowercased() {
    case "jpg", "jpeg": return "image/jpeg"
    case "png":         return "image/png"
    case "webp":        return "image/webp"
    default:            return "image/jpeg"
    }
}

// MARK: - Ollama request

func toJpegData(path: String) -> Data? {
    let ext = (path as NSString).pathExtension.lowercased()
    if ["jpg", "jpeg", "png"].contains(ext) {
        return try? Data(contentsOf: URL(fileURLWithPath: path))
    }
    // Convert webp (and other formats) to JPEG via sips, capped at 1500px to stay under Ollama's request size limit
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString + ".jpg").path
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    proc.arguments = ["-s", "format", "jpeg", "-Z", "1500", path, "--out", tmp]
    proc.standardOutput = FileHandle.nullDevice
    proc.standardError = FileHandle.nullDevice
    try? proc.run(); proc.waitUntilExit()
    let data = try? Data(contentsOf: URL(fileURLWithPath: tmp))
    try? FileManager.default.removeItem(atPath: tmp)
    return data
}

func extractWines(from imagePath: String) -> PhotoResult {
    let filename = (imagePath as NSString).lastPathComponent
    let start = Date()

    guard let imgData = toJpegData(path: imagePath) else {
        return PhotoResult(filename: filename, wines: [], parseErrors: [],
                          httpStatus: nil, networkError: "could not read/convert file",
                          rawLineCount: 0, durationSeconds: 0)
    }

    let b64 = imgData.base64EncodedString()
    // /api/chat with assistant pre-fill of "{" bypasses Qwen3-VL thinking mode.
    let body: [String: Any] = [
        "model": model,
        "messages": [
            ["role": "user", "content": extractionPrompt, "images": [b64]],
            ["role": "assistant", "content": "{"]
        ],
        "stream": false,
        "options": ["temperature": 0.1]
    ]

    guard let url = URL(string: "\(ollamaBase)/api/chat"),
          let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
        return PhotoResult(filename: filename, wines: [], parseErrors: [],
                          httpStatus: nil, networkError: "could not build request",
                          rawLineCount: 0, durationSeconds: 0)
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = bodyData
    request.timeoutInterval = 180

    var responseData: Data?
    var httpStatus: Int?
    var networkErrorMsg: String?

    let sem = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: request) { data, response, error in
        httpStatus = (response as? HTTPURLResponse)?.statusCode
        responseData = data
        networkErrorMsg = error?.localizedDescription
        sem.signal()
    }.resume()
    sem.wait()

    let duration = Date().timeIntervalSince(start)

    if let err = networkErrorMsg {
        return PhotoResult(filename: filename, wines: [], parseErrors: [],
                          httpStatus: httpStatus, networkError: err,
                          rawLineCount: 0, durationSeconds: duration)
    }

    guard httpStatus == 200, let responseData else {
        return PhotoResult(filename: filename, wines: [], parseErrors: [],
                          httpStatus: httpStatus, networkError: "HTTP \(httpStatus ?? -1)",
                          rawLineCount: 0, durationSeconds: duration)
    }

    // /api/chat non-stream: message.content holds the response text.
    // Prepend "{" to restore the pre-filled opening brace.
    guard let envelope = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
          let message = envelope["message"] as? [String: Any],
          let content = message["content"] as? String else {
        let preview = String(data: responseData, encoding: .utf8).map { String($0.prefix(200)) } ?? "(binary)"
        return PhotoResult(filename: filename, wines: [], parseErrors: [("(envelope)", preview)],
                          httpStatus: 200, networkError: nil,
                          rawLineCount: 0, durationSeconds: duration)
    }
    let rawText = "{" + content

    // Parse JSONL — one wine per line
    let lines = rawText
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }

    var wines: [WineObject] = []
    var parseErrors: [(line: String, error: String)] = []

    for line in lines {
        guard let lineData = line.data(using: .utf8) else { continue }
        do {
            let wine = try JSONDecoder().decode(WineObject.self, from: lineData)
            wines.append(wine)
        } catch {
            // Skip lines that are clearly not JSON objects (e.g. thinking text)
            if line.hasPrefix("{") {
                parseErrors.append((line: String(line.prefix(120)), error: error.localizedDescription))
            }
        }
    }

    return PhotoResult(filename: filename, wines: wines, parseErrors: parseErrors,
                      httpStatus: 200, networkError: nil,
                      rawLineCount: lines.count, durationSeconds: duration)
}

// MARK: - Discover photos

let resourcesDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("resources")

let extensions = Set(["jpg", "jpeg", "png", "webp"])
let photoPaths: [String]

do {
    let items = try FileManager.default.contentsOfDirectory(at: resourcesDir,
        includingPropertiesForKeys: nil)
    photoPaths = items
        .filter { extensions.contains($0.pathExtension.lowercased()) }
        .map(\.path)
        .sorted()
} catch {
    print("ERROR: could not read resources/ directory: \(error)")
    exit(1)
}

guard !photoPaths.isEmpty else {
    print("ERROR: no image files found in resources/")
    exit(1)
}

// MARK: - Verify Ollama is reachable

let pingURL = URL(string: "\(ollamaBase)/api/tags")!
let pingDone = DispatchSemaphore(value: 0)
var ollamaReachable = false
URLSession.shared.dataTask(with: pingURL) { data, resp, _ in
    ollamaReachable = (resp as? HTTPURLResponse)?.statusCode == 200
    pingDone.signal()
}.resume()
pingDone.wait()

guard ollamaReachable else {
    print("ERROR: Ollama not reachable at \(ollamaBase)")
    print("Start it with: ollama serve")
    exit(1)
}

// MARK: - Run eval

print("Running extraction eval against \(photoPaths.count) photos using \(model)")
print("Each inference takes ~10–60s depending on hardware.\n")

var allResults: [PhotoResult] = []

for (idx, path) in photoPaths.enumerated() {
    let filename = (path as NSString).lastPathComponent
    print("[\(idx+1)/\(photoPaths.count)] \(filename)…", terminator: " ")
    fflush(stdout)

    let result = extractWines(from: path)
    allResults.append(result)

    if let err = result.networkError {
        print("ERROR — \(err)")
    } else {
        let lowConf = result.wines.filter { ($0.confidence ?? 1.0) < 0.7 }.count
        let confStr = lowConf > 0 ? " (\(lowConf) low-conf)" : ""
        let parseStr = result.parseErrors.isEmpty ? "" : " \(result.parseErrors.count) parse error(s)"
        print("\(result.wines.count) wines\(confStr)\(parseStr) in \(String(format: "%.1f", result.durationSeconds))s")
    }

    if verbose {
        for wine in result.wines {
            let conf = wine.confidence.map { String(format: "%.2f", $0) } ?? "?"
            let vintage = wine.vintage ?? "NV"
            let section = wine.listSection.map { " [\($0)]" } ?? ""
            print("    \(conf) \(wine.name) \(vintage)\(section)")
        }
        for (line, err) in result.parseErrors {
            print("    PARSE ERROR: \(err)")
            print("    LINE: \(line)")
        }
    }
}

// MARK: - Summary

print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("EXTRACTION EVAL REPORT — \(model)")
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

let successful = allResults.filter { $0.networkError == nil && $0.httpStatus == 200 }
let totalWines = successful.flatMap { $0.wines }.count
let totalParseErrors = successful.flatMap { $0.parseErrors }.count
let allConfidences = successful.flatMap { $0.wines }.compactMap { $0.confidence }
let avgConf = allConfidences.isEmpty ? 0.0 : allConfidences.reduce(0, +) / Double(allConfidences.count)
let lowConfCount = allConfidences.filter { $0 < 0.7 }.count
let avgDuration = successful.isEmpty ? 0.0 : successful.map { $0.durationSeconds }.reduce(0, +) / Double(successful.count)

print("Per-photo breakdown:")
print(String(repeating: "─", count: 76))

let maxName = allResults.map { $0.filename.count }.max() ?? 20
for r in allResults {
    let name = r.filename.padding(toLength: max(maxName, 20), withPad: " ", startingAt: 0)
    if let err = r.networkError {
        print("  \(name)  ERROR: \(err)")
    } else {
        let wines = String(r.wines.count).padding(toLength: 3, withPad: " ", startingAt: 0)
        let parseE = r.parseErrors.isEmpty ? "  " : "\(r.parseErrors.count)!"
        let lowC = r.wines.filter { ($0.confidence ?? 1.0) < 0.7 }.count
        let lowStr = lowC > 0 ? " \(lowC) low-conf" : ""
        let dur = String(format: "%.1fs", r.durationSeconds)
        print("  \(name)  \(wines) wines  \(parseE)  \(dur)\(lowStr)")
    }
}

print(String(repeating: "─", count: 76))
print()
print("Total wines extracted:   \(totalWines) across \(successful.count)/\(allResults.count) photos")
print("Avg wines per photo:     \(successful.isEmpty ? 0 : totalWines / successful.count)")
print("Parse errors:            \(totalParseErrors)")
print("Avg confidence:          \(String(format: "%.2f", avgConf))")
print("Low-confidence (<0.7):   \(lowConfCount)/\(allConfidences.count) (\(allConfidences.isEmpty ? 0 : Int(Double(lowConfCount)/Double(allConfidences.count)*100))%)")
print("Avg inference time:      \(String(format: "%.1f", avgDuration))s per photo")

// Section header coverage
let winesWithSection = successful.flatMap { $0.wines }.filter { $0.listSection != nil }.count
print("Section header captured: \(winesWithSection)/\(totalWines) wines (\(totalWines == 0 ? 0 : Int(Double(winesWithSection)/Double(totalWines)*100))%)")

// Vintage coverage
let winesWithVintage = successful.flatMap { $0.wines }.filter { $0.vintage != nil }.count
print("Vintage captured:        \(winesWithVintage)/\(totalWines) wines (\(totalWines == 0 ? 0 : Int(Double(winesWithVintage)/Double(totalWines)*100))%)")

// Price coverage
let winesWithPrice = successful.flatMap { $0.wines }.filter { $0.price != nil }.count
print("Price captured:          \(winesWithPrice)/\(totalWines) wines (\(totalWines == 0 ? 0 : Int(Double(winesWithPrice)/Double(totalWines)*100))%)")

print()
if totalParseErrors == 0 && avgConf >= 0.8 && lowConfCount == 0 {
    print("VERDICT: ✓ PASS — prompt is production-ready")
} else if avgConf >= 0.7 && Double(totalParseErrors) / max(Double(totalWines), 1) < 0.05 {
    print("VERDICT: ~ MARGINAL — acceptable but review low-confidence wines; run --verbose to inspect")
} else {
    print("VERDICT: ✗ FAIL — iterate on WineExtractionPrompt.swift before shipping")
    if totalParseErrors > 0 {
        print("  → \(totalParseErrors) lines failed to parse as JSON — model may be adding commentary")
    }
    if avgConf < 0.7 {
        print("  → avg confidence \(String(format: "%.2f", avgConf)) — model is uncertain; check dim/angled photos")
    }
}
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
