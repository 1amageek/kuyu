import SwiftUI

public struct TimelineSliderView: View {
    @Binding var time: Double
    let range: ClosedRange<Double>

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Timeline")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Text(String(format: "%.2f s", time))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $time, in: range)
                .tint(.accentColor)
        }
        .padding(12)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    TimelineSliderView(time: .constant(4.0), range: 0...20)
        .padding()
}
