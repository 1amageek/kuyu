import Charts
import SwiftUI

public struct MetricChartView: View {
    let title: String
    let unit: String
    let samples: [MetricSample]
    let lineColor: Color

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary)
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
                plot.background(.quaternary.opacity(0.15))
            }
            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(minHeight: 120)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator, lineWidth: 1)
        )
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
