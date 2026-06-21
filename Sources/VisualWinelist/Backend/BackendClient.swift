import Foundation

enum BackendError: Error, LocalizedError, Sendable {
    case unreachable(String)
    case scannerBusy
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .unreachable(let url):
            return "Backend not reachable at \(url).\n\nIs the server running? Try: docker compose up"
        case .scannerBusy:
            return "The scanner is busy — another scan is in progress"
        case .httpError(let code):
            return "Backend error (HTTP \(code))"
        }
    }
}

struct BackendClient: Sendable {
    let baseURL: URL

    // MARK: - Health

    func checkHealth() async throws -> HealthResponse {
        let url = baseURL.appendingPathComponent("health")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw BackendError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try JSONDecoder().decode(HealthResponse.self, from: data)
    }

    // MARK: - Scan

    /// Stream SSE events from POST /scan. Mirrors OllamaClient.swift's bytes(for:) pattern (D5).
    func scan(photoData: Data) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let magic = photoData.prefix(4).map { String(format: "%02X", $0) }.joined(separator: " ")
                    print("[DIAG] scan: \(photoData.count) bytes, magic=\(magic), url=\(baseURL)/scan")

                    let request = buildScanRequest(photoData: photoData)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let http = response as? HTTPURLResponse else {
                        print("[DIAG] scan: non-HTTP response")
                        continuation.finish(throwing: BackendError.unreachable(baseURL.absoluteString))
                        return
                    }
                    print("[DIAG] scan: HTTP \(http.statusCode), content-type=\(http.value(forHTTPHeaderField: "Content-Type") ?? "nil")")
                    if http.statusCode == 503 {
                        print("[DIAG] scan: SCANNER_BUSY")
                        continuation.finish(throwing: BackendError.scannerBusy)
                        return
                    }
                    guard http.statusCode == 200 else {
                        print("[DIAG] scan: non-200 status \(http.statusCode)")
                        continuation.finish(throwing: BackendError.httpError(http.statusCode))
                        return
                    }

                    var parser = SSEParser()
                    var lineCount = 0
                    for try await line in bytes.lines {
                        lineCount += 1
                        if !line.isEmpty && !line.hasPrefix(":") {
                            print("[DIAG] SSE line \(lineCount): \(line.prefix(120))")
                        }
                        if let event = parser.feed(line: line) {
                            print("[DIAG] SSE event yielded: \(event)")
                            continuation.yield(event)
                        }
                    }
                    print("[DIAG] scan: stream finished, \(lineCount) lines total")
                    continuation.finish()

                } catch let urlError as URLError
                    where urlError.code == .cannotConnectToHost
                    || urlError.code == .networkConnectionLost
                    || urlError.code == .cannotFindHost
                    || urlError.code == .timedOut
                {
                    print("[DIAG] scan: URLError unreachable: \(urlError)")
                    continuation.finish(throwing: BackendError.unreachable(baseURL.absoluteString))
                } catch {
                    print("[DIAG] scan: unexpected error: \(error)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Image fetch

    func fetchImage(wineId: String) async throws -> Data {
        let url = baseURL
            .appendingPathComponent("wines")
            .appendingPathComponent(wineId)
            .appendingPathComponent("image")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw BackendError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return data
    }

    // MARK: - Private

    private func buildScanRequest(photoData: Data) -> URLRequest {
        let url = baseURL.appendingPathComponent("scan")
        let boundary = UUID().uuidString

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type")
        // SSE streams run for several minutes on large wine lists — prevent timeout.
        request.timeoutInterval = 300

        var body = Data()
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"image\"; filename=\"scan.jpg\"\r\n")
        body.appendString("Content-Type: image/jpeg\r\n\r\n")
        body.append(photoData)
        body.appendString("\r\n--\(boundary)--\r\n")
        request.httpBody = body

        return request
    }
}

private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) { append(data) }
    }
}
