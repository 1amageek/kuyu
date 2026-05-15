import Charts
import SwiftUI

struct LearningMetricChartView: View {
    let title: String
    let subtitle: String
    let unit: String
    let samples: [MetricSample]
    let tint: Color
    let trailingValue: Double?
    let xAxisLabel: String

    init(
        title: String,
        subtitle: String,
        unit: String,
        samples: [MetricSample],
        tint: Color,
        trailingValue: Double?,
        xAxisLabel: String = "episode"
    ) {
        self.title = title
        self.subtitle = subtitle
        self.unit = unit
        self.samples = samples
        self.tint = tint
        self.trailingValue = trailingValue
        self.xAxisLabel = xAxisLabel
    }

    var body: some View {
        GroupBox {
            if samples.isEmpty {
                placeholder
            } else {
                Chart(Array(samples.enumerated()), id: \.offset) { _, sample in
                    LineMark(
                        x: .value("Step", sample.time),
                        y: .value(unit, sample.value)
                    )
                    .foregroundStyle(tint)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Step", sample.time),
                        y: .value(unit, sample.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [tint.opacity(0.26), tint.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .chartXAxisLabel(xAxisLabel)
                .chartYAxisLabel(unit)
                .chartLegend(.hidden)
                .frame(minHeight: 250)
            }
        } label: {
            HStack {
                Label(title, systemImage: "waveform.path.ecg")
                Spacer()
                if let trailingValue {
                    Text(String(format: "%.2f", trailingValue))
                        .font(.system(.callout, design: .monospaced).weight(.semibold))
                        .foregroundStyle(tint)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: KuyuRadius.medium, style: .continuous)
                .fill(.black.opacity(0.16))
            Text("No metric samples yet")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minHeight: 250)
    }
}
