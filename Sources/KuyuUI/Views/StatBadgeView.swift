import SwiftUI

public struct StatBadgeView: View {
    let passed: Bool
    
    public init(passed: Bool) {
        self.passed = passed
    }

    public var body: some View {
        Text(passed ? "PASS" : "FAIL")
            .font(KuyuUITheme.monoFont(size: 10))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(passed ? KuyuUITheme.success.opacity(0.2) : KuyuUITheme.warning.opacity(0.2))
            .foregroundStyle(passed ? KuyuUITheme.success : KuyuUITheme.warning)
            .clipShape(Capsule())
    }
}

#Preview {
    HStack {
        StatBadgeView(passed: true)
        StatBadgeView(passed: false)
    }
    .padding()
    .background(KuyuUITheme.panelBackground)
}
