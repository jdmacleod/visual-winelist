import Foundation

protocol BackendClientProtocol: Sendable {
    func checkHealth() async throws -> HealthResponse
    func scan(photoData: Data) -> AsyncThrowingStream<SSEEvent, Error>
    func fetchImage(wineId: String) async throws -> Data
}

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
                    let request = buildScanRequest(photoData: photoData)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let http = response as? HTTPURLResponse else {
                        continuation.finish(throwing: BackendError.unreachable(baseURL.absoluteString))
                        return
                    }
                    if http.statusCode == 503 {
                        continuation.finish(throwing: BackendError.scannerBusy)
                        return
                    }
                    guard http.statusCode == 200 else {
                        continuation.finish(throwing: BackendError.httpError(http.statusCode))
                        return
                    }

                    var parser = SSEParser()
                    // bytes.lines silently drops empty lines, which breaks SSE dispatch
                    // (empty lines signal event boundaries). Iterate raw bytes instead,
                    // splitting on \n to preserve empty lines exactly like IOSScanSession.
                    var lineBuffer = Data()
                    for try await byte in bytes {
                        if byte == UInt8(ascii: "\n") {
                            let line = String(data: lineBuffer, encoding: .utf8) ?? ""
                            lineBuffer = Data()
                            if let event = parser.feed(line: line) {
                                continuation.yield(event)
                            }
                        } else if byte != UInt8(ascii: "\r") {
                            lineBuffer.append(byte)
                        }
                    }
                    if !lineBuffer.isEmpty {
                        let line = String(data: lineBuffer, encoding: .utf8) ?? ""
                        if let event = parser.feed(line: line) {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()

                } catch let urlError as URLError
                    where urlError.code == .cannotConnectToHost
                    || urlError.code == .networkConnectionLost
                    || urlError.code == .cannotFindHost
                    || urlError.code == .timedOut
                {
                    continuation.finish(throwing: BackendError.unreachable(baseURL.absoluteString))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Image fetch

    func fetchImage(wineId: String) async throws -> Data {
        let url =
            baseURL
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

extension BackendClient: BackendClientProtocol {}

private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) { append(data) }
    }
}
