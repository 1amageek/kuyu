import SwiftUI

public struct TimelineSliderView: View {
    @Binding var time: Double
    let range: ClosedRange<Double>

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Timeline")
                    .font(KuyuUITheme.titleFont(size: 14))
                    .foregroundStyle(KuyuUITheme.textPrimary)
                Spacer()
                Text(String(format: "%.2f s", time))
                    .font(KuyuUITheme.monoFont(size: 12))
                    .foregroundStyle(KuyuUITheme.textSecondary)
            }
            Slider(value: $time, in: range)
                .tint(KuyuUITheme.accent)
        }
        .padding(12)
        .background(KuyuUITheme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(KuyuUITheme.panelHighlight, lineWidth: 1)
        )
    }
}

#Preview {
    TimelineSliderView(time: .constant(4.0), range: 0...20)
        .padding()
        .background(KuyuUITheme.background)
}
