import SwiftUI

/// A point-in-time event rendered as a tick on the timeline track.
public struct TimelineMarker: Identifiable {
    public enum Kind {
        case swap
        case hfStress
        case fault
        case recovery

        var color: Color {
            switch self {
            case .swap: .yellow
            case .hfStress: .orange
            case .fault: .red
            case .recovery: .green
            }
        }
    }

    public let time: Double
    public let kind: Kind
    public let label: String

    public var id: String { "\(label)@\(time)" }

    public init(time: Double, kind: Kind, label: String) {
        self.time = time
        self.kind = kind
        self.label = label
    }
}

public struct TimelineSliderView: View {
    @Binding var time: Double
    let range: ClosedRange<Double>
    let markers: [TimelineMarker]
    let seed: UInt64?

    public init(
        time: Binding<Double>,
        range: ClosedRange<Double>,
        markers: [TimelineMarker] = [],
        seed: UInt64? = nil
    ) {
        self._time = time
        self.range = range
        self.markers = markers
        self.seed = seed
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
            HStack(spacing: KuyuSpacing.md) {
                Text("Timeline")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if let seed {
                    Text("seed \(seed)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !markers.isEmpty {
                    markerLegend
                }
            }

            HStack(spacing: KuyuSpacing.md) {
                ZStack(alignment: .top) {
                    Slider(value: $time, in: range)
                        .tint(.accentColor)
                    markerTrack
                        .allowsHitTesting(false)
                }
                Text(String(format: "%.2f s", time))
                    .font(.system(.callout, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .trailing)
            }
        }
    }

    private var markerTrack: some View {
        GeometryReader { proxy in
            let span = max(range.upperBound - range.lowerBound, .leastNonzeroMagnitude)
            ForEach(markers) { marker in
                let fraction = (marker.time - range.lowerBound) / span
                if fraction >= 0, fraction <= 1 {
                    Rectangle()
                        .fill(marker.kind.color)
                        .frame(width: 2, height: 14)
                        .position(x: proxy.size.width * CGFloat(fraction), y: 7)
                        .help("\(marker.label) @ \(String(format: "%.2fs", marker.time))")
                }
            }
        }
        .frame(height: 14)
    }

    private var markerLegend: some View {
        HStack(spacing: KuyuSpacing.sm) {
            ForEach(Array(Set(markers.map(\.kind))), id: \.self) { kind in
                HStack(spacing: 2) {
                    Circle().fill(kind.color).frame(width: 6, height: 6)
                    Text(legendLabel(kind))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func legendLabel(_ kind: TimelineMarker.Kind) -> String {
        switch kind {
        case .swap: "swap"
        case .hfStress: "HF"
        case .fault: "fault"
        case .recovery: "recovery"
        }
    }
}

extension TimelineMarker.Kind: Hashable {}

#Preview {
    TimelineSliderView(
        time: .constant(4.0),
        range: 0...20,
        markers: [
            TimelineMarker(time: 5.0, kind: .swap, label: "sensor swap"),
            TimelineMarker(time: 8.0, kind: .hfStress, label: "impulse"),
            TimelineMarker(time: 12.5, kind: .fault, label: "ground violation"),
        ],
        seed: 2001
    )
    .padding()
}
