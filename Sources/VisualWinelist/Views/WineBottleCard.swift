import SwiftUI
import AppKit

struct WineBottleCard: View {
    let state: WineState
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottom) {
                imageLayer
                nameOverlay
                if state.isLowConfidence {
                    uncertaintyBadge
                }
            }
        }
        .buttonStyle(.plain)
        .aspectRatio(3/4, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
    }

    @ViewBuilder
    private var imageLayer: some View {
        switch state {
        case .ready(_, let data):
            if let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                PlaceholderBottle(wine: state.wine)
            }
        case .extracting, .fetchingImage:
            PlaceholderBottle(wine: state.wine)
                .overlay {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.white)
                }
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
            VStack(alignment: .leading, spacing: 2) {
                Text(state.wine.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let vintage = state.wine.vintage {
                    Text(vintage)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var uncertaintyBadge: some View {
        Text("?")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .padding(4)
            .background(.orange, in: Circle())
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
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
        if appellation.contains("champagne") || appellation.contains("prosecco") { return .yellow.opacity(0.8) }
        if appellation.contains("rioja") { return .orange }
        return .purple
    }

    private func regionFlag(for appellation: String) -> String {
        let lower = appellation.lowercased()
        if lower.contains("bordeaux") || lower.contains("burgundy") ||
           lower.contains("champagne") || lower.contains("france") { return "🇫🇷" }
        if lower.contains("napa") || lower.contains("sonoma") ||
           lower.contains("california") || lower.contains("oregon") ||
           lower.contains("washington") { return "🇺🇸" }
        if lower.contains("tuscany") || lower.contains("barolo") ||
           lower.contains("italy") || lower.contains("sicily") { return "🇮🇹" }
        if lower.contains("rioja") || lower.contains("spain") ||
           lower.contains("priorat") { return "🇪🇸" }
        if lower.contains("argentina") || lower.contains("mendoza") { return "🇦🇷" }
        if lower.contains("chile") { return "🇨🇱" }
        if lower.contains("australia") || lower.contains("barossa") { return "🇦🇺" }
        if lower.contains("new zealand") { return "🇳🇿" }
        if lower.contains("portugal") { return "🇵🇹" }
        if lower.contains("germany") || lower.contains("mosel") { return "🇩🇪" }
        return "🍷"
    }
}
