import SwiftUI
import UIKit

struct WineBottleCard: View {
    let state: WineState
    @AppStorage("showPriceOverlay") private var showPriceOverlay = false

    var body: some View {
        ZStack(alignment: .bottom) {
            imageLayer
            nameOverlay
            if showPriceOverlay, let price = state.wine.price {
                priceOverlay(price)
            }
            if state.isLowConfidence {
                uncertaintyBadge
            }
        }
        .aspectRatio(3 / 5, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: .cornerRadiusCard))
        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
    }

    @ViewBuilder
    private var imageLayer: some View {
        switch state {
        case .ready(_, let data):
            ZStack {
                PlaceholderBottle(wine: state.wine)
                if let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                }
            }
        case .extracting, .fetchingImage:
            PlaceholderBottle(wine: state.wine)
                .overlay { ShimmerOverlay() }
        case .placeholder:
            PlaceholderBottle(wine: state.wine)
        }
    }

    private var nameOverlay: some View {
        LinearGradient(
            colors: [.clear, .black.opacity(0.75)],
            startPoint: .center,
            endPoint: .bottom
        )
        .overlay(alignment: .bottom) {
            Text(state.wine.name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func priceOverlay(_ price: String) -> some View {
        Text(price)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(.black.opacity(0.6), in: Capsule())
            .padding(5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var uncertaintyBadge: some View {
        Text("?")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(4)
            .background(.orange, in: Circle())
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }
}

private struct ShimmerOverlay: View {
    @State private var phase: Double = -0.4

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: phase - 0.25),
                .init(color: .white.opacity(0.35), location: phase),
                .init(color: .clear, location: phase + 0.25),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .blendMode(.overlay)
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                phase = 1.4
            }
        }
        .onDisappear {
            phase = -0.4
        }
    }
}

struct PlaceholderBottle: View {
    let wine: WineObject

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [bottleColor.opacity(0.6), bottleColor],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(spacing: 8) {
                Image(systemName: "wineglass")
                    .font(.system(size: 40))
                    .foregroundStyle(.white.opacity(0.7))
                if let appellation = wine.appellation {
                    Text(regionFlag(for: appellation))
                        .font(.system(size: 24))
                }
            }
        }
    }

    private var bottleColor: Color {
        guard let appellation = wine.appellation?.lowercased() else { return .purple }
        if appellation.contains("bordeaux") || appellation.contains("burgundy") { return .purple }
        if appellation.contains("napa") || appellation.contains("sonoma") { return .indigo }
        if appellation.contains("tuscany") || appellation.contains("barolo") { return .red }
        if appellation.contains("champagne") || appellation.contains("prosecco") {
            return .yellow.opacity(0.8)
        }
        if appellation.contains("rioja") { return .orange }
        return .purple
    }

    private func regionFlag(for appellation: String) -> String {
        let lower = appellation.lowercased()
        if lower.contains("bordeaux") || lower.contains("burgundy") || lower.contains("champagne")
            || lower.contains("france")
        {
            return "🇫🇷"
        }
        if lower.contains("napa") || lower.contains("sonoma") || lower.contains("california")
            || lower.contains("oregon") || lower.contains("washington")
        {
            return "🇺🇸"
        }
        if lower.contains("tuscany") || lower.contains("barolo") || lower.contains("italy")
            || lower.contains("sicily")
        {
            return "🇮🇹"
        }
        if lower.contains("rioja") || lower.contains("spain") || lower.contains("priorat") { return "🇪🇸" }
        if lower.contains("argentina") || lower.contains("mendoza") { return "🇦🇷" }
        if lower.contains("chile") { return "🇨🇱" }
        if lower.contains("australia") || lower.contains("barossa") { return "🇦🇺" }
        if lower.contains("new zealand") { return "🇳🇿" }
        if lower.contains("portugal") { return "🇵🇹" }
        if lower.contains("germany") || lower.contains("mosel") { return "🇩🇪" }
        return "🍷"
    }
}
