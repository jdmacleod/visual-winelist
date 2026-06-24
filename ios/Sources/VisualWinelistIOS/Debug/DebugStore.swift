import Foundation
import Observation

/// Singleton accumulator for per-scan timing metrics. Always compiled (not just
/// DEBUG): it feeds both the opt-in telemetry reporter (Release) and the debug
/// HUD (#if DEBUG). All mutations must occur on the MainActor; callers from
/// background queues (e.g. URLSessionDataDelegate) must use
/// Task { @MainActor in DebugStore.shared.* }.
@MainActor
@Observable
final class DebugStore {
    static let shared = DebugStore()

    var lastScan: ScanMetrics?

    // Staged by ContentView.capture() before the resize task runs, consumed by beginScan.
    private var pendingOrigWidth: Int = 0
    private var pendingOrigHeight: Int = 0

    struct ScanMetrics {
        // Server-minted scan id (X-Scan-Id header), the correlation key for telemetry.
        var scanID: String?
        var backendURL: String = ""
        var origWidth: Int = 0
        var origHeight: Int = 0
        var screenshotBytes: Int = 0
        var screenshotWidth: Int = 0
        var screenshotHeight: Int = 0
        // Upload settings in effect for this scan (T5 — tunable for baselines).
        var uploadMaxSide: Int = 0
        var uploadJPEGQuality: Double = 0
        var uploadMs: Int = 0
        var ttfbMs: Int = 0
        // URLSessionTaskTransactionMetrics phase breakdown (T2).
        var dnsMs: Int?
        var tcpMs: Int?
        var requestMs: Int?
        var responseMs: Int?
        // Gap between request-fully-sent and first response byte = pure server
        // time-to-first-byte (responseStartDate − requestEndDate). Isolates the
        // "server hasn't replied yet" wait from upload/connect (Diagnostic 1).
        var waitMs: Int?
        // Server-side body-receive time, from the complete event (T1).
        var receiveMs: Int?
        // Time from scan start to the first wine yielded by Ollama — the real
        // time-to-first-image gate (Diagnostic 3, from the complete event).
        var firstWineMs: Int?
        var ollamaMs: Int?
        var imageMs: Int?
        var sommelierMs: Int?
        var totalMs: Int?
        // Aggregated per-wine Brave timing, from the complete event (T4).
        var braveSearchMs: Int?
        var imageDownloadMs: Int?
        var wineCount: Int?
        var cacheHits: Int?
        // Count of SSE events that failed to decode this scan. Surfaced as a
        // red parse_err row so a CompleteSSEPayload (or any event) decode break
        // is visible on-device instead of only print()'d to the console.
        var parseErrorCount: Int = 0
        var eventTimeline: [(label: String, ms: Int)] = []
    }

    func stageOriginalSize(width: Int, height: Int) {
        pendingOrigWidth = width
        pendingOrigHeight = height
    }

    func beginScan(screenshotBytes: Int, width: Int, height: Int, backendURL: String) {
        lastScan = ScanMetrics(
            backendURL: backendURL,
            origWidth: pendingOrigWidth,
            origHeight: pendingOrigHeight,
            screenshotBytes: screenshotBytes,
            screenshotWidth: width,
            screenshotHeight: height,
            uploadMaxSide: ScanSettings.uploadMaxSide,
            uploadJPEGQuality: Double(ScanSettings.uploadJPEGQuality)
        )
        pendingOrigWidth = 0
        pendingOrigHeight = 0
    }

    func scanFailed() {
        lastScan = nil
    }

    func recordScanId(_ id: String) {
        lastScan?.scanID = id
    }

    func recordUpload(ms: Int) {
        lastScan?.uploadMs = ms
    }

    func recordTTFB(ms: Int) {
        lastScan?.ttfbMs = ms
    }

    func recordTransactionMetrics(
        dns: Int?, tcp: Int?, request: Int?, response: Int?, wait: Int?
    ) {
        lastScan?.dnsMs = dns
        lastScan?.tcpMs = tcp
        lastScan?.requestMs = request
        lastScan?.responseMs = response
        lastScan?.waitMs = wait
    }

    func recordEvent(label: String, ms: Int) {
        lastScan?.eventTimeline.append((label: label, ms: ms))
    }

    func recordParseError() {
        lastScan?.parseErrorCount += 1
    }

    func recordComplete(payload: CompleteSSEPayload) {
        lastScan?.receiveMs = payload.receive_ms
        lastScan?.firstWineMs = payload.first_wine_ms
        lastScan?.ollamaMs = payload.ollama_ms
        lastScan?.imageMs = payload.image_ms
        lastScan?.sommelierMs = payload.sommelier_ms
        lastScan?.totalMs = payload.total_ms
        lastScan?.braveSearchMs = payload.brave_search_ms
        lastScan?.imageDownloadMs = payload.image_download_ms
        lastScan?.wineCount = payload.wine_count
        lastScan?.cacheHits = payload.cache_hits
    }
}
