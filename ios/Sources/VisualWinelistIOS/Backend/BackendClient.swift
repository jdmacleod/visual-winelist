import Foundation

enum BackendError: Error, LocalizedError, Sendable {
    case unreachable(String)
    case scannerBusy
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .unreachable(let url):
            return "Backend not reachable at \(url).\n\nCheck that you're on the same WiFi network as the server."
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

    /// Returns a stream of SSE events and a session handle for cancellation (T10).
    /// Call session.cancel() when the view dismisses to release the URLSession task.
    func scan(photoData: Data) -> (stream: AsyncThrowingStream<SSEEvent, Error>, session: IOSScanSession) {
        let magic = photoData.prefix(4).map { String(format: "%02X", $0) }.joined(separator: " ")
        print("[DIAG] BackendClient.scan: \(photoData.count) bytes, magic=\(magic), url=\(baseURL)/scan")
        let request = buildScanRequest(photoData: photoData)
        return IOSScanSession.make(request: request)
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
