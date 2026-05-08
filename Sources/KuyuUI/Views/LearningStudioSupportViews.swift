import SwiftUI

struct HeaderMetricView: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "--" : value)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(minWidth: 82, alignment: .leading)
    }
}

struct PreviewStatusView: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: KuyuSpacing.sm) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .monospacedDigit()
        }
        .font(.caption)
    }
}

struct DoubleSliderView: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let display: String

    var body: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
            HStack {
                Text(label)
                Spacer()
                Text(display)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
        }
    }
}

struct IntegerStepperView: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        Stepper(value: $value, in: range) {
            HStack {
                Text(label)
                Spacer()
                Text("\(value)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
