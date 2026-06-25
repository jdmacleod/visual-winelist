import SwiftUI

/// Branded waiting screen: a wine-bottle silhouette that fills with the app's
/// wineRed as the scan advances, on a warm cream background (replaces the old
/// black screen). Keeps the stage message and Cancel.
struct ScanningView: View {
    let progress: Double
    let message: String
    let onCancel: () -> Void

    private static let creamTop = Color(red: 0.99, green: 0.97, blue: 0.97)
    private static let creamBottom = Color(red: 0.96, green: 0.92, blue: 0.93)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Self.creamTop, Self.creamBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                FillingBottle(progress: progress)
                    .frame(width: 150, height: 300)

                Text(message.isEmpty ? "Scanning wine list…" : message)
                    .font(.headline)
                    .foregroundStyle(.wineRed)
                    .multilineTextAlignment(.center)
                    .animation(.default, value: message)
                    .padding(.horizontal, 32)

                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .tint(.wineRed)
                    .padding(.top, 4)
            }
        }
    }
}

/// Bottle outline with a wineRed "wine" level that rises with `progress` (0...1).
/// A gentle surface bob gives the liquid life during the long analyze wait;
/// it is disabled under Reduce Motion.
private struct FillingBottle: View {
    let progress: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bob: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let level = max(0, min(1, CGFloat(progress)))
            ZStack(alignment: .bottom) {
                // Empty interior wash so the silhouette reads even at 0%.
                BottleShape().fill(Color.wineRed.opacity(0.08))

                // The wine: a rising rectangle masked to the bottle shape.
                Rectangle()
                    .fill(Color.wineRed)
                    .frame(height: geo.size.height * level + bob)
                    .frame(maxWidth: .infinity, alignment: .bottom)
                    .mask(BottleShape().frame(width: geo.size.width, height: geo.size.height))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: progress)

                BottleShape().stroke(Color.wineRed, lineWidth: 3)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                bob = 4
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Scanning in progress")
        .accessibilityValue("\(Int(progress * 100)) percent")
    }
}

/// A simple wine-bottle silhouette normalized to its frame.
struct BottleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let centerX = rect.midX
        // `frac` is a signed fraction of width from center / a fraction of height.
        func posX(_ frac: CGFloat) -> CGFloat { centerX + frac * width }
        func posY(_ frac: CGFloat) -> CGFloat { rect.minY + frac * rect.height }

        let lip: CGFloat = 0.065
        let neck: CGFloat = 0.05
        let body: CGFloat = 0.22

        var path = Path()
        path.move(to: CGPoint(x: posX(-lip), y: posY(0.0)))
        path.addLine(to: CGPoint(x: posX(lip), y: posY(0.0)))
        path.addLine(to: CGPoint(x: posX(lip), y: posY(0.045)))
        path.addLine(to: CGPoint(x: posX(neck), y: posY(0.075)))
        path.addLine(to: CGPoint(x: posX(neck), y: posY(0.24)))
        path.addQuadCurve(
            to: CGPoint(x: posX(body), y: posY(0.36)),
            control: CGPoint(x: posX(neck), y: posY(0.34)))
        path.addLine(to: CGPoint(x: posX(body), y: posY(0.92)))
        path.addQuadCurve(
            to: CGPoint(x: posX(body - 0.06), y: posY(0.985)),
            control: CGPoint(x: posX(body), y: posY(0.985)))
        path.addLine(to: CGPoint(x: posX(-(body - 0.06)), y: posY(0.985)))
        path.addQuadCurve(
            to: CGPoint(x: posX(-body), y: posY(0.92)),
            control: CGPoint(x: posX(-body), y: posY(0.985)))
        path.addLine(to: CGPoint(x: posX(-body), y: posY(0.36)))
        path.addQuadCurve(
            to: CGPoint(x: posX(-neck), y: posY(0.24)),
            control: CGPoint(x: posX(-neck), y: posY(0.34)))
        path.addLine(to: CGPoint(x: posX(-neck), y: posY(0.075)))
        path.addLine(to: CGPoint(x: posX(-lip), y: posY(0.045)))
        path.closeSubpath()
        return path
    }
}
