import Foundation
import ImageIO
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
            // Defensive: treat a missing dependency as degraded even if the status
            // string disagrees, so the Home/camera banner is reliable. The backend
            // already reports status="degraded" when ollama/brave are down, but we
            // don't want a stale or optimistic status field to hide a real problem.
            var issues: [String] = []
            if !health.ollama { issues.append("Ollama not running — run: ollama serve") }
            if !health.brave_key { issues.append("BRAVE_API_KEY not configured on server") }
            if issues.isEmpty && health.isOK {
                backendStatus = .ok
            } else {
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
        scanMessage = "Sending photo…"
        errorMessage = nil

        // Telemetry outcome, captured by the diagnostics defer below. Defaults to
        // interrupted (stream ended without a complete event and without a caught
        // error); set to completed/error/cancelled by the branches that run.
        var scanOutcome = "interrupted"

        defer {
            isScanning = false
            scanMessage = ""
            activeScanSession = nil
        }

        // Report opt-in diagnostics, then run the HUD lifecycle. wineCount is set by
        // recordComplete() for every complete event (including error paths), so nil
        // means complete was never received. Keep the panel when a parse error
        // occurred so the parse_err evidence survives. The send reads the metrics
        // before any wipe, and is a no-op unless the user enabled "Send Diagnostics?".
        defer {
            let metrics = DebugStore.shared.lastScan
            ScanTelemetryReporter.report(
                metrics: metrics, outcome: scanOutcome, backendURL: backend.baseURL)
            if metrics?.wineCount == nil && (metrics?.parseErrorCount ?? 0) == 0 {
                DebugStore.shared.scanFailed()
            }
        }

        debugBeginScan(photoData: photoData)
        let (stream, scanSession) = backend.scan(photoData: photoData)
        activeScanSession = scanSession

        do {
            var extractedCount = 0
            var notesReceived = 0
            var sawAnalyzing = false

            try await withThrowingTaskGroup(of: Void.self) { group in
                for try await event in stream {
                    switch event {
                    case .wine(let wine):
                        guard !wines.contains(where: { $0.wine == wine }) else { continue }
                        extractedCount += 1
                        wines.append(.extracting(wine))
                        scanMessage = "Found \(wines.count) wine\(wines.count == 1 ? "" : "s")…"

                    case .image(let payload):
                        group.addTask { try await self.handleImageEvent(payload) }

                    case .notes(let payload):
                        handleNotesEvent(payload)
                        // Phase 2: sommelier notes stream one per wine. Show progress so
                        // the ~N-second pass after the gallery fills isn't a silent wait.
                        notesReceived += 1
                        scanMessage =
                            "Getting tasting notes… (\(notesReceived)/\(max(notesReceived, extractedCount)))"

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
                        scanOutcome = "error"

                    case .complete(let payload):
                        // SSE stream is done — unblock action buttons now. Image
                        // fetch tasks continue in the background via the group.
                        DebugStore.shared.recordComplete(payload: payload)
                        scanOutcome = "completed"
                        isScanning = false
                        let hit = payload.cache_hits
                        scanMessage =
                            "\(payload.wine_count) wine\(payload.wine_count == 1 ? "" : "s")"
                            + (hit > 0 ? " · \(hit) from cache" : "")

                    case .status(let stage):
                        // First token back from Ollama: analysis is actively running.
                        if stage == "analyzing", wines.isEmpty {
                            sawAnalyzing = true
                            scanMessage = "Analyzing the wine list…"
                        }

                    case .ping:
                        // First byte (the ": ready" flush) confirms the upload landed and
                        // the backend is spinning Ollama up — but no model output yet.
                        // Stay on "Getting ready…" until the analyzing status arrives.
                        if wines.isEmpty && !sawAnalyzing {
                            scanMessage = "Getting ready to analyze…"
                        }

                    case .parseError:
                        print("[SSE] parse error — malformed event from backend")
                        DebugStore.shared.recordParseError()
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
            scanOutcome = "cancelled"  // user cancelled — leave wines as-is, don't show error
        } catch BackendError.scannerBusy {
            errorMessage = "Scanner is busy — another scan is in progress"
            scanOutcome = "error"
        } catch BackendError.invalidImage {
            errorMessage =
                "Image format not supported — use JPEG. Try taking a photo directly rather than importing."
            scanOutcome = "error"
        } catch BackendError.unreachable(let url) {
            errorMessage = "Backend not reachable at \(url)\n\nCheck WiFi and try again"
            scanOutcome = "error"
        } catch {
            if let urlErr = error as? URLError, urlErr.code == .cancelled {
                scanOutcome = "cancelled"  // URLSession cancel on view dismiss
            } else {
                errorMessage = "Scan failed — \(error.localizedDescription)"
                scanOutcome = "error"
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

    private func debugBeginScan(photoData: Data) {
        var imgWidth = 0, imgHeight = 0
        let srcOpts = [kCGImageSourceShouldCache: false] as CFDictionary
        if let src = CGImageSourceCreateWithData(photoData as CFData, srcOpts),
            let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        {
            imgWidth = props[kCGImagePropertyPixelWidth] as? Int ?? 0
            imgHeight = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        }
        DebugStore.shared.beginScan(
            screenshotBytes: photoData.count,
            width: imgWidth,
            height: imgHeight,
            backendURL: backend.baseURL.absoluteString
        )
    }

    private func handleNotesEvent(_ payload: NotesSSEPayload) {
        guard let idx = wines.firstIndex(where: { $0.wine.wineId == payload.wine_id }) else { return }
        var wine = wines[idx].wine
        wine.tastingNote = payload.tasting_note
        wine.pairings = payload.pairings
        wines[idx] = wines[idx].withUpdatedWine(wine)
    }
}
