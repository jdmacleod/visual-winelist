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
            var uploadMs: Int = 0
            var ttfbMs: Int = 0
            var ollamaMs: Int?
            var totalMs: Int?
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
                screenshotHeight: height
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

        func recordEvent(label: String, ms: Int) {
            lastScan?.eventTimeline.append((label: label, ms: ms))
        }

        func recordComplete(payload: CompleteSSEPayload) {
            lastScan?.ollamaMs = payload.ollama_ms
            lastScan?.totalMs = payload.total_ms
        }
    }
#endif
