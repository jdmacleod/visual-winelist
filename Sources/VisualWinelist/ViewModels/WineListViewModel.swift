import Foundation

@MainActor
class WineListViewModel: ObservableObject {
    @Published var wines: [WineState] = []
    @Published var isScanning = false
    @Published var scanMessage = ""
    @Published var errorMessage: String?
    @Published var selectedWine: WineObject?
    @Published var backendStatus: BackendStatus = .unknown
    @Published var notesIncomplete: Bool = false

    enum BackendStatus {
        case unknown, ok, degraded(String), unreachable
    }

    private let backend: any BackendClientProtocol

    init(backendURL: URL) {
        self.backend = BackendClient(baseURL: backendURL)
    }

    init(backend: any BackendClientProtocol) {
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
                if !health.ollama { issues.append("Ollama not running (start with: ollama serve)") }
                if !health.brave_key { issues.append("BRAVE_API_KEY not set on server") }
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

    func clear() {
        wines = []
        selectedWine = nil
        errorMessage = nil
        notesIncomplete = false
    }

    // MARK: - Private

    private func performScan(photoData: Data) async {
        isScanning = true
        scanMessage = "Sending photo to backend…"
        errorMessage = nil
        notesIncomplete = false

        var receivedComplete = false
        var userCancelled = false

        defer {
            isScanning = false
            scanMessage = ""
            if !receivedComplete && !userCancelled && !wines.isEmpty {
                notesIncomplete = true
            }
        }

        do {
            var extractedCount = 0

            for try await event in backend.scan(photoData: photoData) {
                switch event {
                case .wine(let wine):
                    guard !wines.contains(where: { $0.wine == wine }) else { continue }
                    extractedCount += 1
                    wines.append(.extracting(wine))
                    scanMessage = "\(wines.count) wine\(wines.count == 1 ? "" : "s") found…"

                case .image(let payload):
                    // Fire-and-forget: don't block the SSE loop while fetching image bytes.
                    Task { await self.handleImageEvent(payload) }

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
                    receivedComplete = true
                    let hit = payload.cache_hits
                    scanMessage =
                        "\(payload.wine_count) wine\(payload.wine_count == 1 ? "" : "s")"
                        + (hit > 0 ? " · \(hit) from cache" : "")

                case .ping:
                    break

                case .parseError:
                    break
                }
            }

            // Only show the generic hint if no specific error was already surfaced
            // from an SSE event: error payload. An OLLAMA_DOWN or similar error
            // would otherwise be silently overwritten by this message.
            if extractedCount == 0 && errorMessage == nil {
                errorMessage = "No wines found — try a flatter angle or better lighting"
            }

        } catch is CancellationError {
            userCancelled = true
        } catch BackendError.scannerBusy {
            errorMessage = "Scanner is busy — another scan is in progress"
        } catch BackendError.unreachable(let url) {
            errorMessage = "Backend not reachable at \(url)\n\nIs the server running? Try: docker compose up"
        } catch {
            errorMessage = "Scan failed — \(error.localizedDescription)"
        }
    }

    private func handleImageEvent(_ payload: ImageSSEPayload) async {
        guard let idx = wines.firstIndex(where: { $0.wine.wineId == payload.wine_id }) else { return }

        if payload.placeholder {
            wines[idx] = .placeholder(wines[idx].wine)
            return
        }

        wines[idx] = .fetchingImage(wines[idx].wine)
        do {
            let imageData = try await backend.fetchImage(wineId: payload.wine_id)
            // Re-find index since array may have shifted during the await
            if let currentIdx = wines.firstIndex(where: { $0.wine.wineId == payload.wine_id }) {
                wines[currentIdx] = .ready(wines[currentIdx].wine, imageData)
            }
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
