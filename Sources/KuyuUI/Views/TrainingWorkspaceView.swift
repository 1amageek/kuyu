import KuyuMLX
import SwiftUI

struct TrainingWorkspaceView: View {
    @Bindable var model: AppViewModel

    private var trainingModel: SimulationViewModel {
        model.simulationViewModel
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KuyuSpacing.xl) {
                phaseContent
                TrainingPhaseNavigationView(model: model)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(KuyuSpacing.xl)
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch model.selectedTrainingPhase {
        case .template:
            templatePhase
        case .environment:
            environmentPhase
        case .strategy:
            strategyPhase
        }
    }

    private var templatePhase: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.lg) {
            phaseHeader(
                title: "Choose a Template",
                subtitle: "Set the experiment objective and initial conditions."
            )
            ExperimentDesignView(model: trainingModel)
        }
    }

    private var environmentPhase: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.lg) {
            phaseHeader(
                title: "Configure the Environment",
                subtitle: "Set the scenario, observation, and execution conditions."
            )
            EnvironmentConfigView(
                model: trainingModel,
                environmentName: $model.selectedEnvironmentName
            )
        }
    }

    private var strategyPhase: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.lg) {
            phaseHeader(
                title: "Design the Learning Strategy",
                subtitle: "Pick one of RL / GA / Hybrid and edit its strategy-specific parameters."
            )
            TrainingStrategyChoiceView(model: trainingModel)
            strategyConfiguration
            RecommendedPresetView(model: trainingModel)
        }
    }

    @ViewBuilder
    private var strategyConfiguration: some View {
        switch trainingModel.learningStrategySelection {
        case .reinforcementLearning:
            ReinforcementLearningConfigView(model: trainingModel)
        case .geneticLearning:
            GeneticLearningConfigView(model: trainingModel)
        case .hybrid:
            VStack(alignment: .leading, spacing: KuyuSpacing.lg) {
                HybridFlowView()
                ReinforcementLearningConfigView(model: trainingModel)
                GeneticLearningConfigView(model: trainingModel)
                HybridIntegrationConfigView(model: trainingModel)
            }
        }
    }

    private func phaseHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct TrainingPhaseNavigationView: View {
    @Bindable var model: AppViewModel

    var body: some View {
        HStack {
            Button {
                if let previous {
                    model.selectedTrainingPhase = previous
                }
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .disabled(previous == nil)

            Spacer()

            Button {
                if let next {
                    model.selectedTrainingPhase = next
                } else {
                    model.selectedWorkspace = .run
                }
            } label: {
                Label(next == nil ? "Continue to Run" : "Next", systemImage: "chevron.right")
            }
        }
        .controlSize(.small)
    }

    private var previous: BoundedTrainingPhase? {
        BoundedTrainingPhase.allCases.last { $0.step < model.selectedTrainingPhase.step }
    }

    private var next: BoundedTrainingPhase? {
        BoundedTrainingPhase.allCases.first { $0.step > model.selectedTrainingPhase.step }
    }
}

private struct TrainingStrategyChoiceView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        HStack(spacing: KuyuSpacing.md) {
            strategyCard(.reinforcementLearning, tint: .blue)
            strategyCard(.geneticLearning, tint: .green)
            strategyCard(.hybrid, tint: .purple)
        }
    }

    private func strategyCard(_ strategy: LearningStrategySelection, tint: Color) -> some View {
        let isSelected = model.learningStrategySelection == strategy
        return Button {
            model.selectLearningStrategy(strategy)
        } label: {
            GroupBox {
                HStack(alignment: .center, spacing: KuyuSpacing.md) {
                    Image(systemName: strategy.systemImage)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 42)
                    VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
                        Text(strategy.title)
                            .font(.headline)
                        Text(strategy.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                        StatusPill(strategy.availabilityLabel, tone: strategy.isExecutable ? .success : .warning)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: KuyuRadius.medium, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .opacity(strategy.isExecutable ? 1 : 0.68)
        .help(strategy.unavailableReason ?? "Executable learning strategy")
        .frame(maxWidth: .infinity)
    }
}

private struct HybridFlowView: View {
    var body: some View {
        GroupBox {
            HStack(spacing: KuyuSpacing.md) {
                flowStep("GA Search", "Generate candidates and explore broadly", "sparkle.magnifyingglass")
                flowArrow
                flowStep("RL Refine", "Improve candidates efficiently", "slider.horizontal.3")
                flowArrow
                flowStep("Evaluate & Select", "Accept/reject via the artifact gate", "checkmark.seal")
                flowArrow
                flowStep("Iterate", "Advance generations", "arrow.triangle.2.circlepath")
            }
            .padding(.vertical, KuyuSpacing.xs)
        } label: {
            Label("Hybrid Flow", systemImage: "arrow.triangle.branch")
                .font(.headline)
        }
    }

    private func flowStep(_ title: String, _ subtitle: String, _ systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var flowArrow: some View {
        Image(systemName: "arrow.right")
            .foregroundStyle(.secondary)
    }
}

private struct RecommendedPresetView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        GroupBox {
            HStack(spacing: KuyuSpacing.md) {
                presetButton("Convergence", preset: .convergence, description: "Run until quality is reached or progress plateaus")
                presetButton("Balanced", preset: .standard, description: "Light convergence search with validation")
                presetButton("Exploration", preset: .full, description: "Widen suites and seeds, search to convergence")
                presetButton("Smoke", preset: .smoke, description: "Small run to catch problems early")
            }
            .padding(.vertical, KuyuSpacing.xs)
        } label: {
            Label("Recommended Presets", systemImage: "sparkles")
                .font(.headline)
        }
    }

    private func presetButton(
        _ title: String,
        preset: LearningCampaignRunPreset,
        description: String
    ) -> some View {
        let isSelected = model.learningCampaignPreset == preset
        return Button {
            model.learningCampaignPreset = preset
        } label: {
            VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
                HStack {
                    Text(title)
                        .font(.callout.weight(.semibold))
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: KuyuRadius.medium, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .padding(-KuyuSpacing.xs)
            }
        }
    }
}
