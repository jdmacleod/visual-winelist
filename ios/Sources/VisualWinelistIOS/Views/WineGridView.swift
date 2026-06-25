import SwiftUI

struct WineGridView: View {
    var viewModel: WineListViewModel
    let onScanMore: () -> Void
    @AppStorage(UserDefaultsKey.showPriceOverlay) private var showPriceOverlay = false

    private let columnCount = 4
    private let gridSpacing: CGFloat = 8
    private let gridPadding: CGFloat = 16

    var body: some View {
        GeometryReader { proxy in
            let cardWidth = max(
                1,
                (proxy.size.width
                    - gridPadding * 2
                    - gridSpacing * CGFloat(columnCount - 1)) / CGFloat(columnCount))
            let columns = Array(
                repeating: GridItem(.fixed(cardWidth), spacing: gridSpacing),
                count: columnCount
            )

            ScrollView {
                LazyVGrid(columns: columns, spacing: gridSpacing) {
                    ForEach(viewModel.wines) { state in
                        NavigationLink {
                            WineDetailView(viewModel: viewModel, snapshot: state)
                        } label: {
                            WineBottleCard(state: state, showPriceOverlay: showPriceOverlay)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(cardLabel(for: state))
                    }
                }
                .padding(gridPadding)
            }
            .safeAreaInset(edge: .bottom) {
                scanMoreBar
            }
        }
    }

    private func cardLabel(for state: WineState) -> String {
        var label = state.wine.name
        if let vintage = state.wine.vintage { label += ", \(vintage)" }
        if state.isLowConfidence { label += ", low confidence" }
        if state.hasNotes { label += ", tasting notes ready" }
        return label
    }

    private var scanMoreBar: some View {
        HStack(spacing: 8) {
            if viewModel.isScanning {
                // Always-visible stage progress (Analyzing… / Found N wines… /
                // Getting tasting notes (k/N)) so it doesn't scroll out of view.
                ProgressView().scaleEffect(0.7)
                Text(viewModel.scanMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Text("\(viewModel.wines.count) wine\(viewModel.wines.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onScanMore) {
                Label("Scan more", systemImage: "camera.viewfinder")
                    .font(.subheadline.bold())
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isScanning)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
}
