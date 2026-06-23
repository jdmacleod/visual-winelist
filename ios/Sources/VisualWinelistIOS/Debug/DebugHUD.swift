#if DEBUG
    import SwiftUI

    struct DebugHUD: View {
        @State private var store = DebugStore.shared

        var body: some View {
            if let m = store.lastScan {
                VStack(alignment: .leading, spacing: 3) {
                    Text("img: \(m.screenshotBytes / 1024) KB")
                    Text("upload: \(m.uploadMs) ms")
                    Text("1st chunk: \(m.firstChunkMs) ms")
                    if let ollama = m.ollamaMs { Text("ollama: \(ollama) ms") }
                    if let total = m.totalMs { Text("total: \(total) ms") }
                    if !m.eventTimeline.isEmpty {
                        WaterfallView(events: m.eventTimeline)
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
    }
#endif
