import SwiftUI
import UIKit

struct WineDetailView: View {
    let state: WineState
    var isScanning: Bool = false

    private var wine: WineObject { state.wine }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                bottleImage
                    .frame(maxWidth: .infinity)
                    .frame(height: 260)
                    .clipped()

                VStack(alignment: .leading, spacing: 20) {
                    header
                    if let note = wine.tastingNote {
                        tastingNoteSection(note)
                    } else if isScanning {
                        notesLoadingSection
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
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}
