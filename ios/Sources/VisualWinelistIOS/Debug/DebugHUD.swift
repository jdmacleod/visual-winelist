#if DEBUG
    import SwiftUI

    struct DebugHUD: View {
        @State private var store = DebugStore.shared
        @State private var expanded = false

        var body: some View {
            if let m = store.lastScan {
                if expanded {
                    expandedPanel(m)
                } else {
                    pill(m)
                }
            }
        }

        @ViewBuilder
        private func pill(_ m: DebugStore.ScanMetrics) -> some View {
            HStack(spacing: 4) {
                Image(systemName: "timer")
                    .imageScale(.small)
                Text(m.totalMs.map { "\($0)ms" } ?? "…")
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
            .padding(10)
            .onTapGesture { expanded = true }
        }

        @ViewBuilder
        private func expandedPanel(_ m: DebugStore.ScanMetrics) -> some View {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("perf")
                        .fontWeight(.semibold)
                    Spacer()
                    Button {
                        expanded = false
                    } label: {
                        Image(systemName: "xmark")
                            .imageScale(.small)
                    }
                }
                Color.white.opacity(0.3)
                    .frame(height: 1)
                    .padding(.vertical, 1)
                Text("img: \(m.screenshotWidth)×\(m.screenshotHeight) · \(m.screenshotBytes / 1024) KB")
                Text("upload: \(m.uploadMs) ms")
                Text("ttfb: \(m.ttfbMs) ms")
                if let ollama = m.ollamaMs { Text("ollama: \(ollama) ms") }
                if let total = m.totalMs { Text("total: \(total) ms") }
                if !m.eventTimeline.isEmpty {
                    ScrollView(.vertical, showsIndicators: true) {
                        WaterfallView(events: m.eventTimeline)
                    }
                    .frame(maxHeight: 180)
                    .padding(.top, 2)
                }
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.white)
            .padding(8)
            .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
            .padding(10)
        }
    }
#endif
