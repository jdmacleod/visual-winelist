import Foundation

enum BackendError: Error, LocalizedError, Sendable {
    case unreachable(String)
    case scannerBusy
    case invalidImage
    case telemetryDisabled
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .unreachable(let url):
            return "Backend not reachable at \(url).\n\nCheck that you're on the same WiFi network as the server."
        case .scannerBusy:
            return "The scanner is busy — another scan is in progress"
        case .invalidImage:
            return "Image format not supported — use JPEG. Try taking a photo directly rather than importing."
        case .telemetryDisabled:
            return "Telemetry is disabled on the server."
        case .httpError(let code):
            return "Backend error (HTTP \(code))"
        }
    }
}

struct BackendClient: Sendable {
    let baseURL: URL
    let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: - Health

    func checkHealth() async throws -> HealthResponse {
        let url = baseURL.appendingPathComponent("health")
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw BackendError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
            }
            return try JSONDecoder().decode(HealthResponse.self, from: data)
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw CancellationError()
        } catch is URLError {
            throw BackendError.unreachable(baseURL.absoluteString)
        }
    }

    // MARK: - Scan

    /// Returns a stream of SSE events and a session handle for cancellation (T10).
    /// Call session.cancel() when the view dismisses to release the URLSession task.
    func scan(photoData: Data) -> (stream: AsyncThrowingStream<SSEEvent, Error>, session: IOSScanSession) {
        let request = buildScanRequest(photoData: photoData)
        return IOSScanSession.make(request: request, configuration: session.configuration)
    }

    // MARK: - Image fetch

    func fetchImage(wineId: String, size: String = "card") async throws -> Data {
        var components = URLComponents(
            url:
                baseURL
                .appendingPathComponent("wines")
                .appendingPathComponent(wineId)
                .appendingPathComponent("image"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "size", value: size)]
        let url = components.url!
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw BackendError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
            }
            return data
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw CancellationError()
        } catch is URLError {
            throw BackendError.unreachable(baseURL.absoluteString)
        }
    }

    // MARK: - Clear image

    func clearWineImage(wineId: String) async throws {
        var request = URLRequest(
            url:
                baseURL
                .appendingPathComponent("wines")
                .appendingPathComponent(wineId)
                .appendingPathComponent("image")
        )
        request.httpMethod = "DELETE"
        do {
            let (_, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw BackendError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
            }
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw CancellationError()
        } catch is URLError {
            throw BackendError.unreachable(baseURL.absoluteString)
        }
    }

    // MARK: - Telemetry

    /// Recent opt-in telemetry reports for the in-app diagnostics viewer.
    func fetchTelemetryReports(limit: Int = 20) async throws -> [TelemetryReport] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("telemetry").appendingPathComponent("scans"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        do {
            let (data, response) = try await session.data(from: components.url!)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 404 { throw BackendError.telemetryDisabled }
            guard (200...299).contains(code) else { throw BackendError.httpError(code) }
            return try JSONDecoder().decode(TelemetryListResponse.self, from: data).scans
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw CancellationError()
        } catch is URLError {
            throw BackendError.unreachable(baseURL.absoluteString)
        }
    }

    /// Delete all stored telemetry; returns how many rows the server removed.
    @discardableResult
    func clearTelemetry() async throws -> Int {
        var request = URLRequest(
            url: baseURL.appendingPathComponent("telemetry").appendingPathComponent("scans")
        )
        request.httpMethod = "DELETE"
        do {
            let (data, response) = try await session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 404 { throw BackendError.telemetryDisabled }
            guard (200...299).contains(code) else { throw BackendError.httpError(code) }
            return (try? JSONDecoder().decode(TelemetryDeleteResponse.self, from: data).deleted) ?? 0
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw CancellationError()
        } catch is URLError {
            throw BackendError.unreachable(baseURL.absoluteString)
        }
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

        // Opt-in scan-image saving (E13). When the user enables it, ask the
        // backend to persist this photo and prune to the chosen retention count.
        // Absent header => backend default (off) governs; nothing is sent here.
        if UserDefaults.standard.bool(forKey: UserDefaultsKey.saveScanImages) {
            request.setValue("1", forHTTPHeaderField: "X-Save-Scan-Image")
            // 0 means the user enabled saving but never touched the picker; match
            // the Preferences default (50) so retention applies from the first scan.
            let stored = UserDefaults.standard.integer(forKey: UserDefaultsKey.scanImageRetention)
            let retention = stored > 0 ? stored : UserDefaultsKey.scanImageRetentionDefault
            request.setValue(String(retention), forHTTPHeaderField: "X-Scan-Image-Retention")
        }

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
