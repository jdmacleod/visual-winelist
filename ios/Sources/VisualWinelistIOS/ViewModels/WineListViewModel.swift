import Foundation
import Observation

@Observable
@MainActor
class WineListViewModel {
    var wines: [WineState] = []
    var isScanning = false
    var scanMessage = ""
    var errorMessage: String?
    var selectedWine: WineObject?
    var backendStatus: BackendStatus = .unknown

    enum BackendStatus {
        case unknown, ok, degraded(String), unreachable
    }

    private let backend: BackendClient
    var backendClient: BackendClient { backend }
    private var activeScanSession: IOSScanSession?

    init(backendURL: URL) {
        self.backend = BackendClient(baseURL: backendURL)
    }

    init(backend: BackendClient) {
        self.backend = backend
    }

    // MARK: - Health

    func checkHealth() async {
        do {
            let health = try await backend.checkHealth()
            if health.isOK {
                backendStatus = .ok
            } else {
                var issues: [String] = []
                if !health.ollama { issues.append("Ollama not running — run: ollama serve") }
                if !health.brave_key { issues.append("BRAVE_API_KEY not configured on server") }
                backendStatus = .degraded(issues.joined(separator: "\n"))
            }
        } catch {
            backendStatus = .unreachable
        }
    }

    // MARK: - Scan

    func scan(photoData: Data) async {
        wines = []
        await performScan(photoData: photoData)
    }

    func appendScan(photoData: Data) async {
        await performScan(photoData: photoData)
    }

    /// Cancel an in-progress scan. Call from onDisappear to prevent resource leaks (T10).
    func cancelScan() {
        activeScanSession?.cancel()
        activeScanSession = nil
        isScanning = false
        scanMessage = ""
    }

    func clear() {
        cancelScan()
        wines = []
        selectedWine = nil
        errorMessage = nil
    }

    // MARK: - Private

    private func performScan(photoData: Data) async {
        isScanning = true
        scanMessage = "Sending photo to backend…"
        errorMessage = nil

        defer {
            isScanning = false
            scanMessage = ""
            activeScanSession = nil
        }

        let (stream, scanSession) = backend.scan(photoData: photoData)
        activeScanSession = scanSession

        do {
            var extractedCount = 0

            try await withThrowingTaskGroup(of: Void.self) { group in
                for try await event in stream {
                    switch event {
                    case .wine(let wine):
                        guard !wines.contains(where: { $0.wine == wine }) else { continue }
                        extractedCount += 1
                        wines.append(.extracting(wine))
                        scanMessage = "\(wines.count) wine\(wines.count == 1 ? "" : "s") found…"

                    case .image(let payload):
                        group.addTask { try await self.handleImageEvent(payload) }

                    case .notes(let payload):
                        handleNotesEvent(payload)

                    case .error(let payload):
                        switch payload.code {
                        case "OLLAMA_DOWN":
                            errorMessage =
                                "Extraction failed — \(payload.message)\n\nIs Ollama running with qwen3-vl:8b? Run: ollama serve"
                        case "OLLAMA_TIMEOUT":
                            errorMessage =
                                "Ollama timed out — the wine list may be too long, or the model is busy. Try a shorter section."
                        default:
                            errorMessage = "Scan error (\(payload.code)): \(payload.message)"
                        }

                    case .complete(let payload):
                        let hit = payload.cache_hits
                        scanMessage =
                            "\(payload.wine_count) wine\(payload.wine_count == 1 ? "" : "s")"
                            + (hit > 0 ? " · \(hit) from cache" : "")

                    case .ping:
                        break

                    case .parseError:
                        print("[SSE] parse error — malformed event from backend")
                    }
                }

                // Only show the generic hint if no specific error was already surfaced
                // from an SSE event: error payload. An OLLAMA_DOWN or similar error
                // would otherwise be silently overwritten by this message.
                if extractedCount == 0 && errorMessage == nil {
                    errorMessage = "No wines found — try a flatter angle or better lighting"
                }
            }  // end withThrowingTaskGroup

        } catch is CancellationError {
            ()  // user cancelled — leave wines as-is, don't show error
        } catch BackendError.scannerBusy {
            errorMessage = "Scanner is busy — another scan is in progress"
        } catch BackendError.invalidImage {
            errorMessage =
                "Image format not supported — use JPEG. Try taking a photo directly rather than importing."
        } catch BackendError.unreachable(let url) {
            errorMessage = "Backend not reachable at \(url)\n\nCheck WiFi and try again"
        } catch {
            if let urlErr = error as? URLError, urlErr.code == .cancelled {
                ()  // URLSession cancel on view dismiss
            } else {
                errorMessage = "Scan failed — \(error.localizedDescription)"
            }
        }
    }

    private func handleImageEvent(_ payload: ImageSSEPayload) async throws {
        guard let idx = wines.firstIndex(where: { $0.wine.wineId == payload.wine_id }) else { return }

        if payload.placeholder {
            wines[idx] = .placeholder(wines[idx].wine)
            return
        }

        wines[idx] = .fetchingImage(wines[idx].wine)
        do {
            let imageData = try await backend.fetchImage(wineId: payload.wine_id)
            if let currentIdx = wines.firstIndex(where: { $0.wine.wineId == payload.wine_id }) {
                wines[currentIdx] = .ready(wines[currentIdx].wine, imageData)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if let currentIdx = wines.firstIndex(where: { $0.wine.wineId == payload.wine_id }) {
                wines[currentIdx] = .placeholder(wines[currentIdx].wine)
            }
        }
    }

    private func handleNotesEvent(_ payload: NotesSSEPayload) {
        guard let idx = wines.firstIndex(where: { $0.wine.wineId == payload.wine_id }) else { return }
        var wine = wines[idx].wine
        wine.tastingNote = payload.tasting_note
        wine.pairings = payload.pairings
        wines[idx] = wines[idx].withUpdatedWine(wine)
    }
}
