import SwiftUI

public struct AttitudeStatValueView: View {
    let label: String
    let value: Double
    let unit: String

    public var body: some View {
        VStack(spacing: 2) {
            Text(label.uppercased())
                .font(KuyuUITheme.monoFont(size: 9))
                .foregroundStyle(KuyuUITheme.textSecondary)
            Text(String(format: "%.1f %@", value, unit))
                .font(KuyuUITheme.monoFont(size: 12))
                .foregroundStyle(KuyuUITheme.textPrimary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(KuyuUITheme.panelHighlight.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    AttitudeStatValueView(label: "Roll", value: 12.3, unit: "deg")
        .padding()
        .background(KuyuUITheme.background)
}
