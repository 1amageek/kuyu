import Foundation
import SwiftUI
import KuyuCore

struct ScenarioDetailView: View {
    @Bindable var model: SimulationViewModel
    @State private var cursorTime: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let scenario = model.selectedScenario {
                let metrics = scenario.metrics

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(scenario.id.scenarioId.rawValue)
                            .font(KuyuUITheme.titleFont(size: 18))
                            .foregroundStyle(KuyuUITheme.textPrimary)
                        HStack {
                            Text("Seed \(scenario.id.seed.rawValue)")
                                .font(KuyuUITheme.bodyFont(size: 12))
                                .foregroundStyle(KuyuUITheme.textSecondary)
                            let recoveryText = scenario.evaluation.recoveryTimeSeconds.map { String(format: "%.2fs", $0) } ?? "n/a"
                            let overshootText = scenario.evaluation.overshootDegrees.map { String(format: "%.2f", $0) } ?? "n/a"
                            let hfText = scenario.evaluation.hfStabilityScore.map { String(format: "%.2f", $0) } ?? "n/a"

                            HStack(spacing: 16) {
                                Label("Recovery: \(recoveryText)", systemImage: "waveform.path.ecg")
                                Label("Overshoot: \(overshootText)", systemImage: "arrow.up.right")
                                Label("HF: \(hfText)", systemImage: "waveform.path")
                            }
                            .font(KuyuUITheme.bodyFont(size: 12))
                            .foregroundStyle(KuyuUITheme.textSecondary)
                        }

                    }
                    Spacer()
                    StatBadgeView(passed: scenario.evaluation.passed)
                }

                let scene = model.sceneState(at: cursorTime)
                let robot = scene?.robots.first
                let angles = robot.map { eulerAngles(from: $0.orientation) } ?? (roll: 0, pitch: 0, yaw: 0)
                let renderInfo = model.renderAssetInfo()
                let profile = model.resolvedProfile(for: scenario)

                gridLayout(
                    columns: 2,
                    profile: profile,
                    angles: angles,
                    metrics: metrics,
                    renderInfo: renderInfo
                )
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Scenario detail")
                        .font(KuyuUITheme.titleFont(size: 18))
                        .foregroundStyle(KuyuUITheme.textPrimary)
                    Text("Select a run and scenario to inspect the dynamics.")
                        .font(KuyuUITheme.bodyFont(size: 13))
                        .foregroundStyle(KuyuUITheme.textSecondary)
                }
                .padding(16)
                .background(KuyuUITheme.panelBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            Spacer()
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
        profile: RobotProfile,
        angles: (roll: Double, pitch: Double, yaw: Double),
        metrics: ScenarioMetrics,
        renderInfo: RenderAssetInfo?
    ) -> some View {
        Grid(alignment: .topLeading, horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(profile.rows.indices, id: \.self) { rowIndex in
                let row = profile.rows[rowIndex]
                if columns == 1 {
                    ForEach(row.items) { item in
                        GridRow {
                            panelView(
                                item: item,
                                columns: columns,
                                angles: angles,
                                metrics: metrics,
                                renderInfo: renderInfo
                            )
                        }
                    }
                } else {
                    GridRow {
                        ForEach(row.items) { item in
                            panelView(
                                item: item,
                                columns: columns,
                                angles: angles,
                                metrics: metrics,
                                renderInfo: renderInfo
                            )
                            .gridCellColumns(item.span)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func panelView(
        item: RobotPanelItem,
        columns: Int,
        angles: (roll: Double, pitch: Double, yaw: Double),
        metrics: ScenarioMetrics,
        renderInfo: RenderAssetInfo?
    ) -> some View {
        switch item.kind {
        case .timeline:
            TimelineSliderView(time: $cursorTime, range: metrics.timeRange)
        case .render:
            WorldRealityView(
                roll: angles.roll,
                pitch: angles.pitch,
                yaw: angles.yaw,
                label: renderInfo?.name ?? "Robot proxy",
                renderInfo: renderInfo
            )
        case .attitude:
            AttitudeIndicatorView(roll: angles.roll, pitch: angles.pitch, yaw: angles.yaw)
        case .tilt:
            MetricChartView(
                title: "Tilt",
                unit: "degrees",
                samples: metrics.tiltDegrees,
                lineColor: KuyuUITheme.accent
            )
        case .omega:
            MetricChartView(
                title: "Omega",
                unit: "rad/s",
                samples: metrics.omega,
                lineColor: KuyuUITheme.warning
            )
        case .speed:
            MetricChartView(
                title: "Speed",
                unit: "m/s",
                samples: metrics.speed,
                lineColor: KuyuUITheme.accent
            )
        case .altitude:
            MetricChartView(
                title: "Altitude",
                unit: "m",
                samples: metrics.altitude,
                lineColor: KuyuUITheme.warning
            )
        }
    }
}

#Preview {
    ScenarioDetailView(model: KuyuUIPreviewFactory.model())
        .frame(width: 840, height: 700)
        .background(KuyuUITheme.background)
}
