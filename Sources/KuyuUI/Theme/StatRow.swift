import SwiftUI

/// A label/value pair with consistent typography.
///
/// Replaces ad-hoc `HStack { Text(label); Spacer(); Text(value) }` rows
/// scattered through the dashboard.
public struct StatRow: View {
    let label: String
    let value: String
    let valueColor: Color?
    let compact: Bool

    public init(label: String, value: String, valueColor: Color? = nil, compact: Bool = false) {
        self.label = label
        self.value = value
        self.valueColor = valueColor
        self.compact = compact
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: KuyuSpacing.sm) {
            Text(label)
                .font(compact ? .caption : .callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(value)
                .font(compact
                      ? .system(.caption, design: .monospaced)
                      : .system(.callout, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(valueColor ?? .primary)
                .lineLimit(1)
        }
    }
}

/// A simple status pill (used in headers/banners).
public struct StatusPill: View {
    public enum Tone {
        case neutral
        case info
        case success
        case warning
        case danger
    }

    let label: String
    let tone: Tone

    public init(_ label: String, tone: Tone = .neutral) {
        self.label = label
        self.tone = tone
    }

    public var body: some View {
        Text(label)
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, KuyuSpacing.sm)
            .padding(.vertical, 3)
            .background(color.opacity(0.14))
            .clipShape(Capsule())
    }

    private var color: Color {
        switch tone {
        case .neutral: return .secondary
        case .info: return .accentColor
        case .success: return .green
        case .warning: return .yellow
        case .danger: return .orange
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
        StatRow(label: "Phase", value: "warmup")
        StatRow(label: "LR", value: "0.001")
        StatRow(label: "Best Score", value: "0.873", valueColor: .green)
        HStack {
            StatusPill("running", tone: .info)
            StatusPill("PASS", tone: .success)
            StatusPill("paused", tone: .warning)
            StatusPill("failed", tone: .danger)
        }
    }
    .padding()
    .frame(width: 320)
}
