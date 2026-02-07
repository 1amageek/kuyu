import SwiftUI

public struct NumberFieldView: View {
    let label: String
    @Binding var value: Double

    public init(label: String, value: Binding<Double>) {
        self.label = label
        self._value = value
    }

    public var body: some View {
        HStack {
            Text(label.uppercased())
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)
            TextField(label, value: $value, format: .number.precision(.fractionLength(2)))
                .textFieldStyle(.roundedBorder)
        }
    }
}

#Preview {
    NumberFieldView(label: "kp", value: .constant(2.0))
        .padding()
}
