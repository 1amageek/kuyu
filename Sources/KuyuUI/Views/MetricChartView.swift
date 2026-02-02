import Charts
import SwiftUI

struct MetricChartView: View {
    let title: String
    let unit: String
    let samples: [MetricSample]
    let lineColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(KuyuUITheme.titleFont(size: 14))
                .foregroundStyle(KuyuUITheme.textPrimary)
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
                plot.background(KuyuUITheme.panelHighlight.opacity(0.15))
            }
            Text(unit)
                .font(KuyuUITheme.bodyFont(size: 11))
                .foregroundStyle(KuyuUITheme.textSecondary)
        }
        .padding(12)
        .background(KuyuUITheme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(KuyuUITheme.panelHighlight, lineWidth: 1)
        )
    }
}

#Preview {
    MetricChartView(
        title: "Tilt",
        unit: "degrees",
        samples: KuyuUIPreviewFactory.samples(),
        lineColor: KuyuUITheme.accent
    )
    .padding()
    .background(KuyuUITheme.background)
}
