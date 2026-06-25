import SwiftUI
import UIKit

struct WineDetailView: View {
    var viewModel: WineListViewModel
    let snapshot: WineState

    @State private var showFlagAlert = false
    @State private var flagToast = false
    @State private var localImageCleared = false
    @State private var detailImageData: Data?

    /// Live card state resolved from the observable view model by id. Tasting notes
    /// and the bottle image stream in AFTER the user opens this view, so rendering
    /// the snapshot captured at navigation time would freeze the card on its
    /// loading placeholder. Falling back to the snapshot covers a wine that has
    /// left the list (e.g. after clear()).
    private var state: WineState {
        viewModel.wines.first(where: { $0.id == snapshot.id }) ?? snapshot
    }
    private var isScanning: Bool { viewModel.isScanning }
    private var backendClient: BackendClient? { viewModel.backendClient }

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
        .task {
            guard let client = backendClient, let wineId = wine.wineId else { return }
            if let data = try? await client.fetchImage(wineId: wineId, size: "detail") {
                withAnimation(.easeIn(duration: 0.25)) {
                    detailImageData = data
                }
            }
        }
    }

    private var placeholderBottle: some View {
        PlaceholderBottle(wine: wine).frame(height: 280)
    }

    @ViewBuilder
    private var bottleImage: some View {
        if localImageCleared {
            placeholderBottle
        } else {
            switch state {
            case .ready(_, let cardData):
                // Try detail image first; fall back to card thumbnail so a corrupt detail
                // response never silently replaces a working grid image with a placeholder.
                let image = detailImageData.flatMap { UIImage(data: $0) } ?? UIImage(data: cardData)
                if let image {
                    ZStack {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .blur(radius: 24)
                            .overlay(Color.black.opacity(0.4))
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 280)
                    .clipped()
                    .overlay(alignment: .bottom) { imageNameOverlay }
                    .id(detailImageData == nil ? 0 : 1)
                    .transition(.opacity)
                } else {
                    placeholderBottle
                }
            default:
                placeholderBottle
            }
        }
    }

    private var imageNameOverlay: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .black.opacity(0.5), location: 0.55),
                .init(color: .black.opacity(0.82), location: 1.0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 120)
        .overlay(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(wine.name)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                if wine.vintage != nil || wine.price != nil || wine.listSection != nil {
                    HStack(spacing: 10) {
                        if let vintage = wine.vintage { Text(vintage) }
                        if let price = wine.price { Text(price) }
                        if let section = wine.listSection { Text(section.uppercased()).opacity(0.75) }
                    }
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
            .padding(.trailing, 60)
            .frame(maxWidth: .infinity, alignment: .leading)
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
