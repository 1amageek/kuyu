import SwiftUI

/// The full simulation surface (3D scene, playback controls, debug panels).
/// Project gating lives in SimulationWindowContentView; this view assumes a
/// usable SimulationViewModel and is reused by the standalone preview app.
public struct SimulationWorkbenchView: View {
    @Bindable var model: SimulationViewModel

    public init(model: SimulationViewModel) {
        self.model = model
    }

    public var body: some View {
        let pose = RobotPoseSnapshot.current(model: model)
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                WorldRealityView(
                    roll: pose.roll,
                    pitch: pose.pitch,
                    yaw: pose.yaw,
                    position: pose.position,
                    label: pose.renderInfo?.name ?? "Robot proxy",
                    renderInfo: pose.renderInfo,
                    jointAngles: pose.jointAngles,
                    jointValues: pose.jointValues,
                    actuatorChannels: pose.actuatorChannels,
                    showsSensorReadouts: model.simulationShowsSensorReadouts
                )
                .id(pose.renderInfo?.url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                playbackControls
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: KuyuSpacing.md) {
                    KuyuSimulationPreviewView(
                        model: model,
                        roll: pose.roll,
                        pitch: pose.pitch,
                        yaw: pose.yaw,
                        position: pose.position,
                        renderInfo: pose.renderInfo,
                        jointAngles: pose.jointAngles,
                        jointValues: pose.jointValues,
                        sensorSamples: pose.sensorSamples,
                        stepIndex: pose.stepIndex,
                        snapshotTime: pose.time
                    )
                    if model.simulationShowsRewardEvents {
                        rewardEvents
                    }
                    collisionLog
                    debugLayers
                }
                .padding(KuyuSpacing.md)
            }
            .frame(width: 420)
        }
        .navigationTitle("Simulation")
    }

    private var playbackControls: some View {
        HStack(spacing: KuyuSpacing.sm) {
            Button { model.runBaseline() } label: {
                Label("Run", systemImage: "play.fill")
            }
            Button { model.pauseRun() } label: {
                Label("Pause", systemImage: "pause.fill")
            }
            .disabled(!model.isRunning)
            Button { model.stopRun() } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .disabled(!model.isRunning)
            Slider(value: $model.simulationPlaybackFraction, in: 0...1)
                .disabled(model.isRunning || model.isLoopRunning)
            Text(String(format: "%3.0f%%", model.simulationPlaybackFraction * 100))
                .font(.system(.caption, design: .monospaced))
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
            Text("Step")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button { model.resetSimulationPlayback() } label: {
                Label("Reset", systemImage: "backward.end.fill")
            }
            .disabled(model.isRunning || model.isLoopRunning)
        }
        .padding(KuyuSpacing.md)
        .background(.bar)
    }

    private var rewardEvents: some View {
        GroupBox {
            Text(model.learningCampaignLatestEvent ?? "No reward event selected.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } label: {
            Label("Reward Events", systemImage: "flag.checkered")
        }
    }

    private var collisionLog: some View {
        GroupBox {
            Text(collisionSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        } label: {
            Label("Collision Log", systemImage: "exclamationmark.triangle")
        }
    }

    private var debugLayers: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                Toggle("Trajectory Overlay", isOn: $model.simulationShowsTrajectoryOverlay)
                Toggle("Sensor Readouts", isOn: $model.simulationShowsSensorReadouts)
                Toggle("Reward Events", isOn: $model.simulationShowsRewardEvents)
            }
        } label: {
            Label("Debug Layers", systemImage: "square.3.layers.3d")
        }
    }

    private var collisionSummary: String {
        guard let evaluation = model.selectedScenario?.evaluation else {
            return "No collision or failure event."
        }
        if let reason = evaluation.failureReason {
            return reason.rawValue
        }
        if let first = evaluation.failures.first {
            return first
        }
        return "No collision or failure event."
    }
}
