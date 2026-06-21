import SwiftUI
#if os(macOS)
    import AppKit
#endif

struct WineDetailView: View {
    let state: WineState
    var isScanning: Bool = false
    var notesIncomplete: Bool = false
    @Environment(\.dismiss) private var dismiss

    private var wine: WineObject { state.wine }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    bottleImage
                        .frame(maxWidth: .infinity)
                        .frame(height: 300)
                        .clipped()

                    VStack(alignment: .leading, spacing: 20) {
                        header
                        if let note = wine.tastingNote {
                            tastingNoteSection(note)
                        } else if isScanning {
                            notesLoadingSection
                        } else if notesIncomplete {
                            notesIncompleteSection
                        }
                        if !wine.pairings.isEmpty { pairingsSection(wine.pairings) }
                        if let description = wine.description { descriptionSection(description) }
                        metadata
                        if wine.confidence < 0.7 { confidenceWarning }
                        Divider()
                        extractionDebug
                    }
                    .padding(24)
                }
            }
            .navigationTitle(wine.name)
            #if os(macOS)
                .navigationSubtitle(wine.vintage ?? "")
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
            .frame(width: 420, height: 620)
        #endif
    }

    @ViewBuilder
    private var bottleImage: some View {
        switch state {
        case .ready(_, let data):
            #if os(macOS)
                if let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    PlaceholderBottle(wine: wine).frame(height: 300)
                }
            #else
                PlaceholderBottle(wine: wine).frame(height: 300)
            #endif
        default:
            PlaceholderBottle(wine: wine).frame(height: 300)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(wine.name)
                    .font(.title2.bold())
                Spacer()
                if let price = wine.price {
                    Text(price)
                        .font(.title3.bold())
                        .foregroundStyle(.secondary)
                }
            }
            if let vintage = wine.vintage {
                Text(vintage)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            if let section = wine.listSection {
                Text(section.uppercased())
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
        }
    }

    private var notesLoadingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TASTING NOTE")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
            Text("Generating…")
                .font(.body)
                .foregroundStyle(.tertiary)
        }
    }

    private var notesIncompleteSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Tasting notes unavailable")
                    .font(.subheadline.bold())
                Text("Connection dropped mid-scan")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private func tastingNoteSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TASTING NOTE")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.body)
        }
    }

    private func pairingsSection(_ pairings: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FOOD PAIRINGS")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
            HStack(spacing: 8) {
                ForEach(pairings, id: \.self) { pairing in
                    Text(pairing)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.secondary.opacity(0.15), in: Capsule())
                }
            }
        }
    }

    private func descriptionSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FROM THE LIST")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.body)
        }
    }

    private var metadata: some View {
        VStack(spacing: 12) {
            if let producer = wine.producer, producer != wine.name {
                row(label: "Producer", value: producer)
            }
            if let variety = wine.variety { row(label: "Grape", value: variety) }
            if let appellation = wine.appellation { row(label: "Region", value: appellation) }
        }
    }

    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.subheadline)
            Spacer()
        }
    }

    private var extractionDebug: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EXTRACTION DEBUG")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 6) {
                debugRow("Wine ID", wine.wineId ?? "(none)")
                debugRow("Raw text", wine.rawText ?? "(none)")
                debugRow("Confidence", String(format: "%.2f", wine.confidence))
                debugRow("Producer", wine.producer ?? "(null)")
                debugRow("Variety", wine.variety ?? "(null)")
                debugRow("Appellation", wine.appellation ?? "(null)")
                debugRow("Section", wine.listSection ?? "(null)")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func debugRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label + ":")
                .fontWeight(.medium)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }

    private var confidenceWarning: some View {
        HStack(spacing: 8) {
            Image(systemName: "questionmark.circle.fill")
                .foregroundStyle(.orange)
            Text("Low extraction confidence — details may be inaccurate")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}
