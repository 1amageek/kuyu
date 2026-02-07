import SwiftUI

public struct AttitudeStatValueView: View {
    let label: String
    let value: Double
    let unit: String

    public var body: some View {
        VStack(spacing: 2) {
            Text(label.uppercased())
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(String(format: "%.1f %@", value, unit))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    AttitudeStatValueView(label: "Roll", value: 12.3, unit: "deg")
        .padding()
}
