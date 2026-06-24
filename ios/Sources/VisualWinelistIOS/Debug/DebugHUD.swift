#if DEBUG
    import SwiftUI

    struct DebugHUD: View {
        @State private var store = DebugStore.shared
        @State private var expanded = false
        @State private var dragOffset: CGSize = .zero
        @State private var lastDragOffset: CGSize = .zero

        // Computed once: "v<short> (<build>) · <built-at>". The built-at is the app
        // executable's modification date, which bumps on every compile/install, so
        // it doubles as a "is this the fresh build?" tell on-device.
        private static let buildMarker: String = {
            let info = Bundle.main.infoDictionary
            let version = info?["CFBundleShortVersionString"] as? String ?? "?"
            let build = info?["CFBundleVersion"] as? String ?? "?"
            var builtAt = "?"
            if let exe = Bundle.main.executableURL,
                let attrs = try? FileManager.default.attributesOfItem(atPath: exe.path),
                let date = attrs[.modificationDate] as? Date
            {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM d HH:mm"
                builtAt = formatter.string(from: date)
            }
            return "v\(version) (\(build)) · \(builtAt)"
        }()

        var body: some View {
            if let m = store.lastScan {
                Group {
                    if expanded {
                        expandedPanel(m)
                    } else {
                        pill(m)
                    }
                }
                .offset(dragOffset)
                .gesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in
                            dragOffset = CGSize(
                                width: lastDragOffset.width + value.translation.width,
                                height: lastDragOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            lastDragOffset = dragOffset
                        }
                )
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
                            .padding(6)
                    }
                    .contentShape(Rectangle())
                }
                Color.white.opacity(0.3)
                    .frame(height: 1)
                    .padding(.vertical, 1)
                // Build marker: confirms the running binary is the build you just
                // made. The timestamp is the app executable's mtime, so it changes
                // on every rebuild/redeploy — if it's not recent, you're on a stale
                // install (see /investigate finding on perf-ttfi).
                Text("build: \(Self.buildMarker)")
                    .foregroundStyle(.green)
                Text("url: \(m.backendURL)")
                if m.origWidth > 0 {
                    Text("orig: \(m.origWidth)×\(m.origHeight)")
                }
                Text("img: \(m.screenshotWidth)×\(m.screenshotHeight) · \(m.screenshotBytes / 1024) KB")
                if m.uploadMaxSide > 0 {
                    Text("upload_cfg: \(m.uploadMaxSide)px q\(String(format: "%.2f", m.uploadJPEGQuality))")
                }
                Text("http_ok: \(m.uploadMs) ms")
                Text("ttfb: \(m.ttfbMs) ms")
                if let dns = m.dnsMs { Text("dns: \(dns) ms") }
                if let tcp = m.tcpMs { Text("tcp: \(tcp) ms") }
                if let request = m.requestMs { Text("req(send): \(request) ms") }
                if let response = m.responseMs { Text("resp: \(response) ms") }
                if let receive = m.receiveMs { Text("recv(server): \(receive) ms") }
                if let ollama = m.ollamaMs { Text("ollama: \(ollama) ms") }
                if let image = m.imageMs { Text("image: \(image) ms") }
                if let brave = m.braveSearchMs { Text("brave_search: \(brave) ms") }
                if let dl = m.imageDownloadMs { Text("img_download: \(dl) ms") }
                if let sommelier = m.sommelierMs { Text("sommelier: \(sommelier) ms") }
                if let total = m.totalMs { Text("total: \(total) ms") }
                if let count = m.wineCount { Text("wines: \(count)") }
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
