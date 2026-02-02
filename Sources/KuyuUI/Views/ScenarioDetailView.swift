import SwiftUI
import kuyu

struct ScenarioDetailView: View {
    @Bindable var model: SimulationViewModel
    @State private var cursorTime: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let scenario = model.selectedScenario {
                let metrics = scenario.metrics

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(scenario.id.scenarioId.rawValue)
                            .font(KuyuUITheme.titleFont(size: 18))
                            .foregroundStyle(KuyuUITheme.textPrimary)
                        Text("Seed \(scenario.id.seed.rawValue)")
                            .font(KuyuUITheme.bodyFont(size: 12))
                            .foregroundStyle(KuyuUITheme.textSecondary)
                    }
                    Spacer()
                    StatBadgeView(passed: scenario.evaluation.passed)
                }

                TimelineSliderView(time: $cursorTime, range: metrics.timeRange)

                let currentEvent = event(at: cursorTime, log: scenario.log)
                let orientation = currentEvent?.stateSnapshot.orientation
                let angles = orientation.map { eulerAngles(from: $0) } ?? (roll: 0, pitch: 0, yaw: 0)

                HStack(alignment: .top, spacing: 16) {
                    AttitudeIndicatorView(roll: angles.roll, pitch: angles.pitch, yaw: angles.yaw)
                        .frame(maxWidth: 260)
                    VStack(spacing: 16) {
                        MetricChartView(
                            title: "Tilt",
                            unit: "degrees",
                            samples: metrics.tiltDegrees,
                            lineColor: KuyuUITheme.accent
                        )
                        MetricChartView(
                            title: "Omega",
                            unit: "rad/s",
                            samples: metrics.omega,
                            lineColor: KuyuUITheme.warning
                        )
                    }
                }
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

    private func event(at time: Double, log: SimulationLog) -> WorldStepLog? {
        guard !log.events.isEmpty else { return nil }
        let dt = log.timeStep.delta
        let index = max(0, min(log.events.count - 1, Int(round(time / dt)) - 1))
        return log.events[index]
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
        .frame(width: 840, height: 700)
        .background(KuyuUITheme.background)
}
