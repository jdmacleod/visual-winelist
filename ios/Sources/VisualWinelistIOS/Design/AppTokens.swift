import SwiftUI

extension CGFloat {
    static let cornerRadiusSmall: CGFloat = 6  // alerts, badges, inline UI elements
    static let cornerRadiusMedium: CGFloat = 8  // overlays, info banners, warning cards
    static let cornerRadiusCard: CGFloat = 10  // wine bottle cards
    static let cornerRadiusLarge: CGFloat = 12  // setup containers, instruction cards
}

extension Color {
    static let wineRed = Color(red: 0.45, green: 0.1, blue: 0.2)
}
