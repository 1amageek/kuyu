import Charts
import SwiftUI

struct DashboardMetricCardView: View {
    let title: String
    let systemImage: String
    let value: String
    let delta: String?
    let samples: [MetricSample]
    let tint: Color

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: systemImage)
                        .foregroundStyle(tint)
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }

                Text(value)
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                HStack(alignment: .bottom, spacing: KuyuSpacing.sm) {
                    Text(delta ?? "--")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(delta == nil ? Color.secondary : Color.green)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer(minLength: 0)

                    sparkline
                        .frame(width: 72, height: 28)
                }
            }
        }
        .frame(minWidth: 132, minHeight: 104)
    }

    @ViewBuilder
    private var sparkline: some View {
        if samples.isEmpty {
            RoundedRectangle(cornerRadius: KuyuRadius.small, style: .continuous)
                .fill(.quaternary)
        } else {
            Chart(Array(samples.enumerated()), id: \.offset) { _, sample in
                LineMark(
                    x: .value("x", sample.time),
                    y: .value("y", sample.value)
                )
                .foregroundStyle(tint)
                .interpolationMethod(.catmullRom)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
        }
    }
}
