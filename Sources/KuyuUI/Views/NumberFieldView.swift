import SwiftUI

struct NumberFieldView: View {
    let label: String
    @Binding var value: Double

    var body: some View {
        HStack {
            Text(label.uppercased())
                .font(KuyuUITheme.monoFont(size: 10))
                .foregroundStyle(KuyuUITheme.textSecondary)
                .frame(width: 50, alignment: .leading)
            TextField(label, value: $value, format: .number.precision(.fractionLength(2)))
                .textFieldStyle(.roundedBorder)
        }
    }
}

#Preview {
    NumberFieldView(label: "kp", value: .constant(2.0))
        .padding()
        .background(KuyuUITheme.background)
}
