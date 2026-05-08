import Charts
import SwiftUI

public struct MetricChartView: View {
    let title: String
    let unit: String
    let samples: [MetricSample]
    let lineColor: Color

    public init(title: String, unit: String, samples: [MetricSample], lineColor: Color) {
        self.title = title
        self.unit = unit
        self.samples = samples
        self.lineColor = lineColor
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Chart(samples) { sample in
                LineMark(
                    x: .value("Time", sample.time),
                    y: .value(title, sample.value)
                )
                .foregroundStyle(lineColor)
                .interpolationMethod(.catmullRom)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5))
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4))
            }
            .chartPlotStyle { plot in
                plot.background(.quaternary.opacity(0.12))
            }
            .frame(minHeight: KuyuLayout.chartMinHeight)
        }
        .padding(KuyuSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: KuyuRadius.medium, style: .continuous)
                .fill(.quaternary.opacity(0.10))
        )
        .clipShape(RoundedRectangle(cornerRadius: KuyuRadius.medium, style: .continuous))
    }
}

#Preview {
    MetricChartView(
        title: "Tilt",
        unit: "degrees",
        samples: KuyuUIPreviewFactory.samples(),
        lineColor: .accentColor
    )
    .padding()
}
