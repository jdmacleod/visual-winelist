#if DEBUG
    import SwiftUI

    struct WaterfallView: View {
        let events: [(label: String, ms: Int)]

        private var maxMs: Int { events.map(\.ms).max() ?? 1 }

        var body: some View {
            // Explicit frame required — GeometryReader inside an overlay collapses to zero height
            // without a fixed constraint.
            GeometryReader { geo in
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(events.indices, id: \.self) { i in
                        let e = events[i]
                        HStack(spacing: 4) {
                            Text(e.label)
                                .frame(width: 72, alignment: .leading)
                            Rectangle()
                                .fill(.teal.opacity(0.8))
                                .frame(
                                    width: max(2, geo.size.width * 0.55 * CGFloat(e.ms) / CGFloat(maxMs)),
                                    height: 10
                                )
                            Text("\(e.ms)ms")
                                .foregroundStyle(.secondary)
                        }
                        .font(.system(size: 10, design: .monospaced))
                    }
                }
            }
            .frame(height: CGFloat(events.count) * 14)
        }
    }
#endif
