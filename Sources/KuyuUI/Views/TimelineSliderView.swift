import SwiftUI

public struct TimelineSliderView: View {
    @Binding var time: Double
    let range: ClosedRange<Double>

    public var body: some View {
        HStack(spacing: KuyuSpacing.md) {
            Text("Timeline")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Slider(value: $time, in: range)
                .tint(.accentColor)
            Text(String(format: "%.2f s", time))
                .font(.system(.callout, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
        }
    }
}

#Preview {
    TimelineSliderView(time: .constant(4.0), range: 0...20)
        .padding()
}
