import Foundation
import SwiftUI
import KuyuCore

public struct ScenarioDetailView: View {
    @Bindable var model: SimulationViewModel
    @State private var cursorTime: Double = 0

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let scenario = model.selectedScenario {
                let metrics = scenario.metrics

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(scenario.id.scenarioId.rawValue)
                            .font(.title3)
                            .foregroundStyle(.primary)
                        HStack {
                            Text("Seed \(scenario.id.seed.rawValue)")
                                .font(.body)
                                .foregroundStyle(.secondary)
                            let recoveryText = scenario.evaluation.recoveryTimeSeconds.map { String(format: "%.2fs", $0) } ?? "n/a"
                            let overshootText = scenario.evaluation.overshootDegrees.map { String(format: "%.2f", $0) } ?? "n/a"
                            let hfText = scenario.evaluation.hfStabilityScore.map { String(format: "%.2f", $0) } ?? "n/a"

                            HStack(spacing: 16) {
                                Label("Recovery: \(recoveryText)", systemImage: "waveform.path.ecg")
                                Label("Overshoot: \(overshootText)", systemImage: "arrow.up.right")
                                Label("HF: \(hfText)", systemImage: "waveform.path")
                            }
                            .font(.body)
                            .foregroundStyle(.secondary)
                        }

                    }
                    Spacer()
                    StatBadgeView(passed: scenario.evaluation.passed)
                }

                let scene = model.currentSceneState(at: cursorTime)
                let robot = scene?.bodies.first
                let angles = robot.map { eulerAngles(from: $0.orientation) } ?? (roll: 0, pitch: 0, yaw: 0)
                let position = robot?.position ?? Axis3(x: 0, y: 0, z: 0)
                let renderInfo = model.renderAssetInfo()
                HSplitView {
                    WorldRealityView(
                        roll: angles.roll,
                        pitch: angles.pitch,
                        yaw: angles.yaw,
                        position: position,
                        label: renderInfo?.name ?? "Robot proxy",
                        renderInfo: renderInfo
                    )
                    ScrollView {
                        gridLayout(
                            columns: 1,
                            angles: angles,
                            metrics: metrics,
                            renderInfo: renderInfo
                        )
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Scenario detail")
                        .font(.title3)
                        .foregroundStyle(.primary)
                    Text("Select a run and scenario to inspect the dynamics.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)        
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

    @ViewBuilder
    private func gridLayout(
        columns: Int,
        angles: (roll: Double, pitch: Double, yaw: Double),
        metrics: ScenarioMetrics,
        renderInfo: RenderAssetInfo?
    ) -> some View {
        Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                panelView(
                    kind: .timeline,
                    angles: angles,
                    metrics: metrics,
                    renderInfo: renderInfo
                )
                .gridCellColumns(columns)
                .frame(minHeight: 70)
            }
            GridRow {
                panelView(
                    kind: .tilt,
                    angles: angles,
                    metrics: metrics,
                    renderInfo: renderInfo
                )
                .gridCellColumns(columns)
                .frame(minHeight: 220)
            }
            GridRow {
                panelView(kind: .attitude, angles: angles, metrics: metrics, renderInfo: renderInfo)
                    .frame(minWidth: 200, minHeight: 120)
                panelView(kind: .omega, angles: angles, metrics: metrics, renderInfo: renderInfo)
                    .frame(minWidth: 200, minHeight: 120)
            }
            GridRow {
                panelView(kind: .speed, angles: angles, metrics: metrics, renderInfo: renderInfo)
                    .frame(minWidth: 200, minHeight: 120)
                panelView(kind: .altitude, angles: angles, metrics: metrics, renderInfo: renderInfo)
                    .frame(minWidth: 200, minHeight: 120)
            }
        }
        .frame(minHeight: 150, idealHeight: 250, maxHeight: 400)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func panelView(
        kind: ScenarioPanelKind,
        angles: (roll: Double, pitch: Double, yaw: Double),
        metrics: ScenarioMetrics,
        renderInfo: RenderAssetInfo?
    ) -> some View {
        switch kind {
        case .timeline:
            TimelineSliderView(time: $cursorTime, range: metrics.timeRange)
        case .attitude:
            AttitudeIndicatorView(roll: angles.roll, pitch: angles.pitch, yaw: angles.yaw)
        case .tilt:
            MetricChartView(
                title: "Tilt",
                unit: "degrees",
                samples: metrics.tiltDegrees,
                lineColor: .accentColor
            )
        case .omega:
            MetricChartView(
                title: "Omega",
                unit: "rad/s",
                samples: metrics.omega,
                lineColor: .orange
            )
        case .speed:
            MetricChartView(
                title: "Speed",
                unit: "m/s",
                samples: metrics.speed,
                lineColor: .accentColor
            )
        case .altitude:
            MetricChartView(
                title: "Altitude",
                unit: "m",
                samples: metrics.altitude,
                lineColor: .orange
            )
        }
    }
}

private enum ScenarioPanelKind {
    case timeline
    case attitude
    case tilt
    case omega
    case speed
    case altitude
}

#Preview {
    ScenarioDetailView(model: KuyuUIPreviewFactory.model())
        .frame(width: 840, height: 700)
}
