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

        struct ScanMetrics {
            var screenshotBytes: Int = 0
            var uploadMs: Int = 0
            var firstChunkMs: Int = 0
            var ollamaMs: Int?
            var totalMs: Int?
            var eventTimeline: [(label: String, ms: Int)] = []
        }

        func beginScan(screenshotBytes: Int) {
            lastScan = ScanMetrics(screenshotBytes: screenshotBytes)
        }

        func scanFailed() {
            lastScan = nil
        }

        func recordUpload(ms: Int) {
            lastScan?.uploadMs = ms
        }

        func recordFirstChunk(ms: Int) {
            lastScan?.firstChunkMs = ms
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
