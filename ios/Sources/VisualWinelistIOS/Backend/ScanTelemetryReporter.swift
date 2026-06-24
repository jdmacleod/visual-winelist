// swiftlint:disable identifier_name
import Foundation
import UIKit

/// Posts opt-in scan diagnostics to POST /telemetry/scan at scan conclusion.
/// No-op unless the user enabled "Send Diagnostics?". Fire-and-forget — telemetry
/// never affects the scan and any failure is ignored.
enum ScanTelemetryReporter {
    @MainActor
    static func report(metrics: DebugStore.ScanMetrics?, outcome: String, backendURL: URL) {
        guard UserDefaults.standard.bool(forKey: UserDefaultsKey.sendDiagnostics) else { return }
        guard let metrics else { return }
        let payload = ScanTelemetryPayload(metrics: metrics, outcome: outcome, backendURL: backendURL)
        guard let body = try? JSONEncoder().encode(payload) else { return }
        var req = URLRequest(url: backendURL.appendingPathComponent("telemetry/scan"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        URLSession.shared.dataTask(with: req).resume()
    }

    static func deviceModel() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = Mirror(reflecting: sysinfo.machine).children.reduce(into: "") { acc, child in
            if let v = child.value as? Int8, v != 0 {
                acc.append(Character(UnicodeScalar(UInt8(v))))
            }
        }
        return machine.isEmpty ? "unknown" : machine
    }
}

private struct ScanTelemetryPayload: Encodable {
    let scan_id: String
    let outcome: String
    let app_version: String?
    let git_sha: String?
    let device_model: String?
    let os_version: String?
    let backend_url: String?
    let upload_bytes: Int?
    let orig_width: Int?
    let orig_height: Int?
    let sent_width: Int?
    let sent_height: Int?
    let upload_max_side: Int?
    let upload_jpeg_quality: Double?
    let dns_ms: Int?
    let tcp_ms: Int?
    let request_ms: Int?
    let response_ms: Int?
    let wait_ms: Int?
    let ttfb_ms: Int?
    let http_ok_ms: Int?
    let receive_ms: Int?
    let first_wine_ms: Int?
    let ollama_ms: Int?
    let image_ms: Int?
    let brave_search_ms: Int?
    let image_download_ms: Int?
    let sommelier_ms: Int?
    let total_ms: Int?
    let wine_count: Int?
    let cache_hits: Int?
    let parse_errors: Int?
    let event_timeline: [Entry]

    struct Entry: Encodable {
        let label: String
        let ms: Int
    }

    @MainActor
    init(metrics m: DebugStore.ScanMetrics, outcome: String, backendURL: URL) {
        scan_id = m.scanID ?? "client-\(UUID().uuidString.prefix(8))"
        self.outcome = outcome
        app_version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        #if GITSHA_GENERATED
            git_sha = GeneratedBuildInfo.gitSHA
        #else
            git_sha = nil
        #endif
        device_model = ScanTelemetryReporter.deviceModel()
        os_version = UIDevice.current.systemVersion
        backend_url = backendURL.absoluteString
        upload_bytes = m.screenshotBytes > 0 ? m.screenshotBytes : nil
        orig_width = m.origWidth > 0 ? m.origWidth : nil
        orig_height = m.origHeight > 0 ? m.origHeight : nil
        sent_width = m.screenshotWidth > 0 ? m.screenshotWidth : nil
        sent_height = m.screenshotHeight > 0 ? m.screenshotHeight : nil
        upload_max_side = m.uploadMaxSide > 0 ? m.uploadMaxSide : nil
        upload_jpeg_quality = m.uploadJPEGQuality > 0 ? m.uploadJPEGQuality : nil
        dns_ms = m.dnsMs
        tcp_ms = m.tcpMs
        request_ms = m.requestMs
        response_ms = m.responseMs
        wait_ms = m.waitMs
        ttfb_ms = m.ttfbMs > 0 ? m.ttfbMs : nil
        http_ok_ms = m.uploadMs > 0 ? m.uploadMs : nil
        receive_ms = m.receiveMs
        first_wine_ms = m.firstWineMs
        ollama_ms = m.ollamaMs
        image_ms = m.imageMs
        brave_search_ms = m.braveSearchMs
        image_download_ms = m.imageDownloadMs
        sommelier_ms = m.sommelierMs
        total_ms = m.totalMs
        wine_count = m.wineCount
        cache_hits = m.cacheHits
        parse_errors = m.parseErrorCount
        event_timeline = m.eventTimeline.map { Entry(label: $0.label, ms: $0.ms) }
    }
}
