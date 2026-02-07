import SwiftUI

public struct StatBadgeView: View {
    let passed: Bool

    public init(passed: Bool) {
        self.passed = passed
    }

    public var body: some View {
        Text(passed ? "PASS" : "FAIL")
            .font(.system(.caption, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(passed ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
            .foregroundStyle(passed ? .green : .orange)
            .clipShape(Capsule())
    }
}

#Preview {
    HStack {
        StatBadgeView(passed: true)
        StatBadgeView(passed: false)
    }
    .padding()
}
