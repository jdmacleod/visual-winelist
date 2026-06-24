#if DEBUG
    import SwiftUI

    struct DebugHUD: View {
        @State private var store = DebugStore.shared
        @State private var expanded = false
        @State private var dragOffset: CGSize = .zero
        @State private var lastDragOffset: CGSize = .zero

        // Computed once: "v<short> (<build>) · <git-sha> · <built-at>". The git SHA
        // is injected at build time by the "Generate GitSHA source" phase
        // (GeneratedBuildInfo.gitSHA); built-at is the executable's mtime, which
        // bumps every compile/install. Together they make "is this the fresh build,
        // and from which commit?" unambiguous on-device.
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
            // GeneratedBuildInfo is emitted by the Xcode "Generate GitSHA source"
            // phase only. `swift build` (SwiftPM/CI) doesn't run that phase, so the
            // symbol is absent there — GITSHA_GENERATED is defined only in the Xcode
            // target, keeping the package build green with a "dev" placeholder.
            #if GITSHA_GENERATED
                let sha = GeneratedBuildInfo.gitSHA
            #else
                let sha = "dev"
            #endif
            return "v\(version) (\(build)) · \(sha) · \(builtAt)"
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
                            // Clamp to <= 0 on both axes. The widget is bottom-right
                            // anchored, so a positive offset drags it OFF the bottom-right
                            // edge (unrecoverable); negative moves it up/left into view.
                            dragOffset = CGSize(
                                width: min(0, lastDragOffset.width + value.translation.width),
                                height: min(0, lastDragOffset.height + value.translation.height)
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
                        // Re-home the widget so the collapsed pill always returns to the
                        // bottom-right anchor. dragOffset is shared with the pill and a
                        // stray drag (the close tap can register as one via the parent
                        // DragGesture) could otherwise strand the pill off-screen with no
                        // control left to recover it.
                        dragOffset = .zero
                        lastDragOffset = .zero
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
                if m.parseErrorCount > 0 {
                    Text("parse_err: \(m.parseErrorCount) — malformed SSE")
                        .foregroundStyle(.red)
                }
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
