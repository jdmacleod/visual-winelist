import Foundation

enum OllamaError: Error, LocalizedError {
    case connectionRefused
    case noWinesFound
    case unexpectedResponse

    var errorDescription: String? {
        switch self {
        case .connectionRefused: return "Ollama is not running. Start it with: ollama serve"
        case .noWinesFound: return "No wines found — try a flatter angle or better lighting"
        case .unexpectedResponse: return "Unexpected response from Ollama"
        }
    }
}

struct OllamaClient: Sendable {
    let baseURL: URL
    let model: String

    init(baseURL: URL = URL(string: "http://localhost:11434")!, model: String = "qwen3-vl:8b") {
        self.baseURL = baseURL
        self.model = model
    }

    func extractWines(from imageData: Data) -> AsyncThrowingStream<WineObject, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let stream = try await startStream(imageData: imageData)
                    var tokenBuffer = ""
                    var wineCount = 0

                    for try await chunk in stream {
                        tokenBuffer += chunk
                        // Parse complete JSON lines from the accumulated token buffer
                        while let newlineRange = tokenBuffer.range(of: "\n") {
                            let line = String(tokenBuffer[tokenBuffer.startIndex..<newlineRange.lowerBound])
                                .trimmingCharacters(in: .whitespaces)
                            tokenBuffer = String(tokenBuffer[newlineRange.upperBound...])

                            if line.hasPrefix("{"), let wine = tryParse(line) {
                                wineCount += 1
                                print(
                                    "[Ollama] \(wine.name) \(wine.vintage ?? "NV") conf=\(String(format: "%.2f", wine.confidence)) raw='\(wine.rawText.map { String($0.prefix(100)) } ?? "(none)")'"
                                )
                                continuation.yield(wine)
                            }
                        }
                        // Check for a complete JSON object without trailing newline
                        let trimmed = tokenBuffer.trimmingCharacters(in: .whitespaces)
                        if trimmed.hasPrefix("{") && trimmed.hasSuffix("}") {
                            if let wine = tryParse(trimmed) {
                                wineCount += 1
                                print(
                                    "[Ollama] \(wine.name) \(wine.vintage ?? "NV") conf=\(String(format: "%.2f", wine.confidence)) raw='\(wine.rawText.map { String($0.prefix(100)) } ?? "(none)")'"
                                )
                                continuation.yield(wine)
                                tokenBuffer = ""
                            }
                        }
                    }

                    if wineCount == 0 {
                        continuation.finish(throwing: OllamaError.noWinesFound)
                    } else {
                        continuation.finish()
                    }
                } catch let urlError as URLError
                    where urlError.code == .cannotConnectToHost
                    || urlError.code == .networkConnectionLost
                {
                    continuation.finish(throwing: OllamaError.connectionRefused)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private

    private func startStream(imageData: Data) async throws -> AsyncThrowingStream<String, Error> {
        // Uses /api/chat with an assistant pre-fill of "{" to bypass Qwen3-VL's thinking mode.
        // Without the pre-fill, the model exhausts its generation budget reasoning internally
        // and produces zero response tokens.
        let body: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "user",
                    "content": WineExtractionPrompt.text,
                    "images": [imageData.base64EncodedString()],
                ],
                [
                    "role": "assistant",
                    "content": "{",
                ],
            ],
            "stream": true,
            "options": ["temperature": 0.1],
        ]

        var request = URLRequest(url: baseURL.appending(path: "/api/chat"))
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw OllamaError.unexpectedResponse
        }

        return AsyncThrowingStream { inner in
            Task {
                // First token is the continuation of the pre-filled "{" — prepend it.
                var firstToken = true
                var lineBuffer = ""
                do {
                    for try await byte in bytes {
                        guard let char = String(bytes: [byte], encoding: .utf8) else { continue }
                        lineBuffer += char
                        if char == "\n" {
                            if var token = parseChunkToken(lineBuffer) {
                                if firstToken { token = "{" + token; firstToken = false }
                                inner.yield(token)
                            }
                            lineBuffer = ""
                        }
                    }
                    inner.finish()
                } catch {
                    inner.finish(throwing: error)
                }
            }
        }
    }

    private struct OllamaChunk: Decodable {
        struct Message: Decodable { let content: String? }
        let message: Message?
        let done: Bool?
    }

    private func parseChunkToken(_ line: String) -> String? {
        guard let data = line.data(using: .utf8),
            let chunk = try? JSONDecoder().decode(OllamaChunk.self, from: data),
            chunk.done != true
        else { return nil }
        return chunk.message?.content
    }

    private func tryParse(_ json: String) -> WineObject? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(WineObject.self, from: data)
    }
}
