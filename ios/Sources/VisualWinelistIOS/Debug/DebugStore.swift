#if DEBUG
    import Foundation
    import Observation

    /// Singleton accumulator for per-scan timing metrics. All mutations must occur on the
    /// MainActor; callers from background queues (e.g. URLSessionDataDelegate) must use
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
            // URLSessionTaskTransactionMetrics phase breakdown (T2, DEBUG only).
            var dnsMs: Int?
            var tcpMs: Int?
            var requestMs: Int?
            var responseMs: Int?
            // Server-side body-receive time, from the complete event (T1).
            var receiveMs: Int?
            var ollamaMs: Int?
            var imageMs: Int?
            var sommelierMs: Int?
            var totalMs: Int?
            // Aggregated per-wine Brave timing, from the complete event (T4).
            var braveSearchMs: Int?
            var imageDownloadMs: Int?
            var wineCount: Int?
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

        func recordUpload(ms: Int) {
            lastScan?.uploadMs = ms
        }

        func recordTTFB(ms: Int) {
            lastScan?.ttfbMs = ms
        }

        func recordTransactionMetrics(dns: Int?, tcp: Int?, request: Int?, response: Int?) {
            lastScan?.dnsMs = dns
            lastScan?.tcpMs = tcp
            lastScan?.requestMs = request
            lastScan?.responseMs = response
        }

        func recordEvent(label: String, ms: Int) {
            lastScan?.eventTimeline.append((label: label, ms: ms))
        }

        func recordComplete(payload: CompleteSSEPayload) {
            lastScan?.receiveMs = payload.receive_ms
            lastScan?.ollamaMs = payload.ollama_ms
            lastScan?.imageMs = payload.image_ms
            lastScan?.sommelierMs = payload.sommelier_ms
            lastScan?.totalMs = payload.total_ms
            lastScan?.braveSearchMs = payload.brave_search_ms
            lastScan?.imageDownloadMs = payload.image_download_ms
            lastScan?.wineCount = payload.wine_count
        }
    }
#endif
