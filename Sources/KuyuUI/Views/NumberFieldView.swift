import SwiftUI

/// A labeled numeric field with optional range clamping, stepper, unit, and help.
/// Values are clamped to `range` on commit so out-of-range input cannot be entered.
public struct NumberFieldView: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>?
    let step: Double
    let fractionLength: Int
    let unit: String?
    let help: String?

    public init(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>? = nil,
        step: Double = 0.1,
        fractionLength: Int = 2,
        unit: String? = nil,
        help: String? = nil
    ) {
        self.label = label
        self._value = value
        self.range = range
        self.step = step
        self.fractionLength = fractionLength
        self.unit = unit
        self.help = help
    }

    public var body: some View {
        HStack(spacing: KuyuSpacing.xs) {
            Text(label.uppercased())
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)
            TextField(label, value: clampedValue, format: .number.precision(.fractionLength(fractionLength)))
                .textFieldStyle(.roundedBorder)
            if let unit {
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Stepper {
                EmptyView()
            } onIncrement: {
                clampedValue.wrappedValue += step
            } onDecrement: {
                clampedValue.wrappedValue -= step
            }
            .labelsHidden()
        }
        .help(helpText)
    }

    /// Writes clamp the value into `range` (if any); reads pass through.
    private var clampedValue: Binding<Double> {
        Binding(
            get: { value },
            set: { newValue in
                guard newValue.isFinite else { return }
                if let range {
                    value = min(max(newValue, range.lowerBound), range.upperBound)
                } else {
                    value = newValue
                }
            }
        )
    }

    private var helpText: String {
        if let help { return help }
        if let range {
            let lo = range.lowerBound.formatted(.number.precision(.fractionLength(0...fractionLength)))
            let hi = range.upperBound.formatted(.number.precision(.fractionLength(0...fractionLength)))
            return "\(label): \(lo)–\(hi)"
        }
        return label
    }
}

#Preview {
    VStack {
        NumberFieldView(label: "kp", value: .constant(2.0), range: 0 ... 100, step: 0.5, help: "Proportional gain")
        NumberFieldView(label: "lr", value: .constant(0.001), range: 0.00001 ... 1, step: 0.0005, fractionLength: 5)
    }
    .padding()
    .frame(width: 320)
}
