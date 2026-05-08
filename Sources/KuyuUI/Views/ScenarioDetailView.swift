import Foundation
import SwiftUI
import KuyuCore

public struct ScenarioDetailView: View {
    @Bindable var model: SimulationViewModel
    @State private var cursorTime: Double = 0

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let scenario = model.selectedScenario {
                let metrics = scenario.metrics
                let scene = model.currentSceneState(at: cursorTime)
                let robot = scene?.bodies.first
                let angles = robot.map { eulerAngles(from: $0.orientation) } ?? (roll: 0, pitch: 0, yaw: 0)
                let position = robot?.position ?? Axis3(x: 0, y: 0, z: 0)
                let renderInfo = model.renderAssetInfo()

                header(scenario: scenario)
                Divider()
                HStack(spacing: 0) {
                    WorldRealityView(
                        roll: angles.roll,
                        pitch: angles.pitch,
                        yaw: angles.yaw,
                        position: position,
                        label: renderInfo?.name ?? "Robot proxy",
                        renderInfo: renderInfo
                    )
                    .frame(minWidth: KuyuLayout.realityMinWidth, maxWidth: .infinity, maxHeight: .infinity)

                    Divider()

                    chartsColumn(metrics: metrics, angles: angles)
                        .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                TimelineSliderView(time: $cursorTime, range: metrics.timeRange)
                    .padding(.horizontal, KuyuSpacing.md)
                    .padding(.vertical, KuyuSpacing.sm)
            } else {
                emptyState
            }
        }
        .onChange(of: model.selectedScenarioKey) { _, _ in
            if let range = model.selectedScenario?.metrics.timeRange {
                cursorTime = range.lowerBound
            }
        }
        .onAppear {
            if let range = model.selectedScenario?.metrics.timeRange {
                cursorTime = range.lowerBound
            }
        }
    }

    private func header(scenario: ScenarioRunRecord) -> some View {
        let recoveryText = scenario.evaluation.recoveryTimeSeconds.map { String(format: "%.2fs", $0) } ?? "n/a"
        let overshootText = scenario.evaluation.overshootDegrees.map { String(format: "%.2f°", $0) } ?? "n/a"
        let hfText = scenario.evaluation.hfStabilityScore.map { String(format: "%.2f", $0) } ?? "n/a"

        return HStack(alignment: .center, spacing: KuyuSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(scenario.id.scenarioId.rawValue)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("Seed \(scenario.id.seed.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: KuyuSpacing.lg) {
                metricChip("Recovery", value: recoveryText, systemImage: "waveform.path.ecg")
                metricChip("Overshoot", value: overshootText, systemImage: "arrow.up.right")
                metricChip("HF", value: hfText, systemImage: "waveform.path")
            }
            StatBadgeView(passed: scenario.evaluation.passed)
        }
        .padding(.horizontal, KuyuSpacing.md)
        .padding(.vertical, KuyuSpacing.sm)
    }

    private func metricChip(_ label: String, value: String, systemImage: String) -> some View {
        HStack(spacing: KuyuSpacing.xs) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
            Text("Scenario detail")
                .font(.title3)
                .foregroundStyle(.primary)
            Text("Select a run and scenario to inspect the dynamics.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(KuyuSpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func chartsColumn(
        metrics: ScenarioMetrics,
        angles: (roll: Double, pitch: Double, yaw: Double)
    ) -> some View {
        let columns = [
            GridItem(.flexible(minimum: 220), spacing: KuyuSpacing.sm),
            GridItem(.flexible(minimum: 220), spacing: KuyuSpacing.sm)
        ]
        return ScrollView {
            LazyVGrid(columns: columns, spacing: KuyuSpacing.sm) {
                MetricChartView(
                    title: "Tilt",
                    unit: "degrees",
                    samples: metrics.tiltDegrees,
                    lineColor: .accentColor
                )
                MetricChartView(
                    title: "Omega",
                    unit: "rad/s",
                    samples: metrics.omega,
                    lineColor: .orange
                )
                MetricChartView(
                    title: "Speed",
                    unit: "m/s",
                    samples: metrics.speed,
                    lineColor: .accentColor
                )
                MetricChartView(
                    title: "Altitude",
                    unit: "m",
                    samples: metrics.altitude,
                    lineColor: .orange
                )
            }
            .padding(KuyuSpacing.sm)
        }
    }

    private func eulerAngles(from quaternion: QuaternionSnapshot) -> (roll: Double, pitch: Double, yaw: Double) {
        let w = quaternion.w
        let x = quaternion.x
        let y = quaternion.y
        let z = quaternion.z

        let sinr = 2 * (w * x + y * z)
        let cosr = 1 - 2 * (x * x + y * y)
        let roll = atan2(sinr, cosr)

        let sinp = 2 * (w * y - z * x)
        let pitch = abs(sinp) >= 1 ? (Double.pi / 2) * (sinp > 0 ? 1 : -1) : asin(sinp)

        let siny = 2 * (w * z + x * y)
        let cosy = 1 - 2 * (y * y + z * z)
        let yaw = atan2(siny, cosy)

        return (roll, pitch, yaw)
    }
}

#Preview {
    ScenarioDetailView(model: KuyuUIPreviewFactory.model())
        .frame(width: 1000, height: 700)
}
