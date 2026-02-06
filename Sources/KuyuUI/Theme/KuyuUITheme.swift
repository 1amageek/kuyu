import SwiftUI

public struct KuyuUITheme {
    public static let background = LinearGradient(
        colors: [
            Color(red: 0.08, green: 0.09, blue: 0.11),
            Color(red: 0.12, green: 0.13, blue: 0.16),
            Color(red: 0.07, green: 0.08, blue: 0.10)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let panelBackground = Color(red: 0.13, green: 0.14, blue: 0.17).opacity(0.9)
    public static let panelHighlight = Color(red: 0.22, green: 0.23, blue: 0.29)
    public static let accent = Color(red: 0.36, green: 0.82, blue: 0.73)
    public static let warning = Color(red: 0.95, green: 0.52, blue: 0.30)
    public static let success = Color(red: 0.42, green: 0.90, blue: 0.52)
    public static let textPrimary = Color(red: 0.95, green: 0.95, blue: 0.97)
    public static let textSecondary = Color(red: 0.70, green: 0.72, blue: 0.78)
    public static let gridLine = Color.white.opacity(0.08)

    public static func titleFont(size: CGFloat) -> Font {
        Font.custom("Avenir Next", size: size).weight(.semibold)
    }

    public static func bodyFont(size: CGFloat) -> Font {
        Font.custom("Avenir Next", size: size)
    }

    public static func monoFont(size: CGFloat) -> Font {
        Font.custom("SF Mono", size: size)
    }
}
