import SwiftUI
import UIKit

struct WineDetailView: View {
    let state: WineState
    var isScanning: Bool = false
    var backendClient: BackendClient? = nil

    @State private var showFlagAlert = false
    @State private var flagToast = false
    @State private var localImageCleared = false

    private var wine: WineObject { state.wine }

    private var hasImage: Bool {
        if localImageCleared { return false }
        if case .ready = state { return true }
        return false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                bottleImage
                    .frame(maxWidth: .infinity)
                    .frame(height: 260)
                    .clipped()
                    .overlay(alignment: .bottomTrailing) {
                        if hasImage {
                            Button {
                                showFlagAlert = true
                            } label: {
                                Image(systemName: "hand.thumbsdown.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 44, height: 44)
                                    .background(.black.opacity(0.55), in: Circle())
                            }
                            .padding(12)
                            .accessibilityLabel("Flag wrong image")
                        }
                    }
                    .alert("Remove image?", isPresented: $showFlagAlert) {
                        Button("Remove", role: .destructive) {
                            Task { await flagImage() }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("The image will need to be re-set by a curator.")
                    }
                    .overlay(alignment: .bottom) {
                        if flagToast {
                            Text("Flagged for review")
                                .font(.caption)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.black.opacity(0.7), in: Capsule())
                                .padding(.bottom, 12)
                                .transition(.opacity)
                        }
                    }

                VStack(alignment: .leading, spacing: 20) {
                    header
                    if let note = wine.tastingNote {
                        tastingNoteSection(note)
                    } else if isScanning {
                        notesLoadingSection
                    } else {
                        notesUnavailableSection
                    }
                    if !wine.pairings.isEmpty { pairingsSection(wine.pairings) }
                    if let desc = wine.description { descriptionSection(desc) }
                    metadata
                    if wine.confidence < 0.7 { confidenceWarning }
                }
                .padding(20)
            }
        }
        .navigationTitle(wine.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var bottleImage: some View {
        if localImageCleared {
            PlaceholderBottle(wine: wine).frame(height: 260)
        } else {
            switch state {
            case .ready(_, let data):
                if let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    PlaceholderBottle(wine: wine).frame(height: 260)
                }
            default:
                PlaceholderBottle(wine: wine).frame(height: 260)
            }
        }
    }

    private func flagImage() async {
        guard let client = backendClient, let wineId = wine.wineId else { return }
        do {
            try await client.clearWineImage(wineId: wineId)
            withAnimation { localImageCleared = true }
            withAnimation { flagToast = true }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation { flagToast = false }
        } catch {
            // silent — image still shows if request failed
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(wine.name)
                .font(.title2.bold())
            if let vintage = wine.vintage {
                Text(vintage)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            if let price = wine.price {
                Text(price)
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

    private var notesUnavailableSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles.slash")
                .foregroundStyle(.secondary)
            Text("Tasting notes unavailable — sommelier was offline when this wine was scanned")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: .cornerRadiusMedium))
    }

    private var notesLoadingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TASTING NOTE")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
            Text("Arriving from sommelier — dark fruit, structured tannins, long finish")
                .font(.body)
                .redacted(reason: .placeholder)
        }
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
        VStack(alignment: .leading, spacing: 8) {
            Text("FOOD PAIRINGS")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(pairings, id: \.self) { pairing in
                        Text(pairing)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.secondary.opacity(0.15), in: Capsule())
                    }
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
        VStack(spacing: 10) {
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

    private var confidenceWarning: some View {
        HStack(spacing: 8) {
            Image(systemName: "questionmark.circle.fill")
                .foregroundStyle(.orange)
            Text("Low extraction confidence — details may be inaccurate")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: .cornerRadiusMedium))
    }
}
