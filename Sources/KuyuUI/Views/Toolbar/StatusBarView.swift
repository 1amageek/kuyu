import SwiftUI

/// Toolbar status bar view that displays current state in the center of the toolbar (Xcode-style)
public struct StatusBarView: View {
    public let mode: AppViewModel.Mode
    public let simulationModel: SimulationViewModel
    public let trainingModel: SimulationViewModel

    public init(mode: AppViewModel.Mode, simulationModel: SimulationViewModel, trainingModel: SimulationViewModel) {
        self.mode = mode
        self.simulationModel = simulationModel
        self.trainingModel = trainingModel
    }

    public var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            statusIndicator

            Divider()
                .frame(height: 20)

            // Mode-specific metrics
            switch mode {
            case .simulation:
                simulationMetrics
            case .training:
                trainingMetrics
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Status Indicator

    @ViewBuilder
    private var statusIndicator: some View {
        switch mode {
        case .simulation:
            Label {
                Text(simulationModel.isRunning ? "Running" : "Ready")
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.medium)
            } icon: {
                Circle()
                    .fill(simulationModel.isRunning ? .green : .secondary)
                    .frame(width: 8, height: 8)
            }

        case .training:
            Label {
                Text(trainingStatusText)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.medium)
            } icon: {
                Circle()
                    .fill(trainingStatusColor)
                    .frame(width: 8, height: 8)
            }
        }
    }

    // MARK: - Simulation Metrics

    @ViewBuilder
    private var simulationMetrics: some View {
        if let state = simulationModel.liveScene {
            // Time
            Text(String(format: "%.1fs", state.time))
                .monospacedDigit()
                .font(.caption)

            if let robot = state.bodies.first {
                Divider().frame(height: 16)

                // Position
                Text(String(format: "Pos: (%.1f, %.1f, %.1f)",
                           robot.position.x, robot.position.y, robot.position.z))
                    .monospacedDigit()
                    .font(.system(.caption, design: .monospaced))
            }

            if simulationModel.isRunning {
                Divider().frame(height: 16)

                // Running indicator
                Label("Running", systemImage: "play.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
        } else {
            Text("No simulation running")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    // MARK: - Training Metrics

    @ViewBuilder
    private var trainingMetrics: some View {
        Text("Phase \(trainingModel.learningCampaignCurrentPhase)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)

        Divider().frame(height: 16)

        Text(String(format: "Progress %.0f%%", trainingModel.learningCampaignProgressFraction * 100))
            .monospacedDigit()
            .font(.system(.caption, design: .monospaced))

        if let state = trainingModel.learningCampaignState {
            Divider().frame(height: 16)
            Text("Accepted \(state.acceptedCount)/\(state.seedCount)")
                .monospacedDigit()
                .font(.system(.caption, design: .monospaced))

            if let latest = state.latestGenerations.first {
                Divider().frame(height: 16)
                Text("Gen \(latest.generationIndex)")
                    .monospacedDigit()
                    .font(.system(.caption, design: .monospaced))
            }
        } else if let reward = trainingModel.rewardAverageSamples.last?.value {
            Divider().frame(height: 16)
            Text(String(format: "Reward %.2f", reward))
                .monospacedDigit()
                .font(.system(.caption, design: .monospaced))
        }
    }

    private var trainingStatusText: String {
        if trainingModel.isLearningCampaignRunning { return "Campaign" }
        if trainingModel.isTraining || trainingModel.isLoopRunning { return "Training" }
        return "Ready"
    }

    private var trainingStatusColor: Color {
        if trainingModel.isLearningCampaignRunning { return .green }
        if trainingModel.isTraining || trainingModel.isLoopRunning { return .blue }
        return .secondary
    }
}
