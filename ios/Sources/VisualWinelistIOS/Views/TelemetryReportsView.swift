import SwiftUI

/// In-app viewer for recent opt-in telemetry reports (GET /telemetry/scans).
/// Read-only; the "what's sent" disclosure in Preferences explains the fields.
struct TelemetryReportsView: View {
    let backendURL: URL

    @State private var reports: [TelemetryReport] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        List {
            if loading {
                HStack {
                    ProgressView()
                    Text("Loading…").foregroundStyle(.secondary)
                }
            } else if let error {
                Text(error).foregroundStyle(.secondary)
            } else if reports.isEmpty {
                Text("No telemetry reports yet. They appear here after scans complete with Send Diagnostics on.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(reports) { report in
                    row(report)
                }
            }
        }
        .navigationTitle("Recent Reports")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func row(_ report: TelemetryReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(report.outcome.capitalized)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(outcomeColor(report.outcome))
                Spacer()
                Text(shortTime(report.received_at))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                if let total = report.total_ms {
                    Label("\(total) ms", systemImage: "clock")
                }
                if let count = report.wine_count {
                    Label("\(count)", systemImage: "wineglass")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let device = report.device_model {
                Text(device).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func outcomeColor(_ outcome: String) -> Color {
        switch outcome {
        case "completed": return .wineRed
        case "error": return .orange
        default: return .secondary
        }
    }

    /// Trim the stored ISO timestamp to a readable "MM-DD HH:MM".
    private func shortTime(_ iso: String) -> String {
        let parts = iso.split(separator: "T")
        guard parts.count == 2 else { return iso }
        let date = parts[0].split(separator: "-").dropFirst().joined(separator: "-")
        let time = parts[1].prefix(5)
        return "\(date) \(time)"
    }

    private func load() async {
        loading = true
        error = nil
        do {
            reports = try await BackendClient(baseURL: backendURL).fetchTelemetryReports()
        } catch is CancellationError {
            // view dismissed mid-load
        } catch {
            self.error = "Couldn't load reports. Check the backend connection."
        }
        loading = false
    }
}
