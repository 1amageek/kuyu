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
                TrainingPhaseNavigationView(selection: $model.selectedTrainingPhase)
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
        case .launch:
            launchPhase
        }
    }

    private var templatePhase: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.lg) {
            phaseHeader(
                title: "テンプレートを選ぶ",
                subtitle: "Experiment の目的と初期条件を決定します。"
            )
            ExperimentDesignView(model: trainingModel)
        }
    }

    private var environmentPhase: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.lg) {
            phaseHeader(
                title: "環境を構成する",
                subtitle: "Scenario と観測・実行条件を設定します。"
            )
            EnvironmentConfigView(model: trainingModel)
        }
    }

    private var strategyPhase: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.lg) {
            phaseHeader(
                title: "学習戦略を設計する",
                subtitle: "RL・GA・ハイブリッドから 1 つ選び、戦略固有のパラメータを編集します。"
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

    private var launchPhase: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.lg) {
            phaseHeader(
                title: "実行プレビュー",
                subtitle: "リソース見積もりと受理ポリシーを確認してから起動します。"
            )
            TrainingLaunchReviewView(model: trainingModel)
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
    @Binding var selection: BoundedTrainingPhase

    var body: some View {
        HStack {
            Button {
                if let previous {
                    selection = previous
                }
            } label: {
                Label("戻る", systemImage: "chevron.left")
            }
            .disabled(previous == nil)

            Spacer()

            Button {
                if let next {
                    selection = next
                }
            } label: {
                Label(selection == .launch ? "実行プレビューへ" : "次へ", systemImage: "chevron.right")
            }
            .disabled(next == nil)
        }
        .controlSize(.small)
    }

    private var previous: BoundedTrainingPhase? {
        BoundedTrainingPhase.allCases.last { $0.step < selection.step }
    }

    private var next: BoundedTrainingPhase? {
        BoundedTrainingPhase.allCases.first { $0.step > selection.step }
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
                flowStep("GA 探索", "候補を生成し広く探索", "sparkle.magnifyingglass")
                flowArrow
                flowStep("RL 微調整", "候補を効率的に改善", "slider.horizontal.3")
                flowArrow
                flowStep("評価 & 選択", "artifact gate で採否", "checkmark.seal")
                flowArrow
                flowStep("繰り返し", "世代を進める", "arrow.triangle.2.circlepath")
            }
            .padding(.vertical, KuyuSpacing.xs)
        } label: {
            Label("ハイブリッドの流れ", systemImage: "arrow.triangle.branch")
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
                presetButton("バランス", preset: .standard, description: "安定した学習と検証のバランス")
                presetButton("5世代確認", preset: .fiveGeneration, description: "8候補を5世代、Mac最適並列で確認")
                presetButton("探索重視", preset: .full, description: "suite と seed を広げて確認")
                presetButton("検証のみ", preset: .smoke, description: "小さく回して問題を早期発見")
            }
            .padding(.vertical, KuyuSpacing.xs)
        } label: {
            Label("おすすめプリセット", systemImage: "sparkles")
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

private struct TrainingLaunchReviewView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.lg) {
            launchChecklist
            HStack(alignment: .top, spacing: KuyuSpacing.lg) {
                launchArtifacts
                launchEstimate
                launchPolicy
            }
        }
    }

    private var launchChecklist: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                checklistRow("テンプレート設定", status: "OK", tone: .success)
                checklistRow("環境設定", status: "OK", tone: .success)
                checklistRow("学習戦略設定", status: "OK", tone: .success)
                checklistRow(
                    "リソース見積もり",
                    status: model.learningCampaignLaunchEstimate == nil ? "未実行" : "OK",
                    tone: model.learningCampaignLaunchEstimate == nil ? .warning : .success
                )
                checklistRow(
                    "Dry Run Validation",
                    status: model.learningCampaignReadiness.status.label,
                    tone: readinessTone
                )
            }
            .padding(.vertical, KuyuSpacing.xs)
        } label: {
            Label("チェックリスト", systemImage: "checklist")
                .font(.headline)
        }
    }

    private var launchArtifacts: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                StatRow(label: "Source Checkpoint", value: compactPath(model.learningCampaignSourceCheckpointPath))
                StatRow(label: "Artifact Root", value: compactPath(model.learningCampaignArtifactDirectory))
                StatRow(label: "Retention", value: model.learningCampaignCompactRetention ? "compact" : "full")
                StatRow(label: "Validation", value: model.learningCampaignReadiness.status.label)
            }
            .padding(.vertical, KuyuSpacing.xs)
        } label: {
            Label("Artifact", systemImage: "shippingbox")
                .font(.headline)
        }
    }

    private var launchEstimate: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                if let estimate = model.learningCampaignLaunchEstimate {
                    StatRow(label: "Scale", value: estimate.scaleLabel)
                    StatRow(label: "Candidates", value: "\(estimate.candidateEvaluations)")
                    StatRow(label: "Regression Rollouts", value: "\(estimate.regressionRollouts)")
                    StatRow(label: "Regression Episodes", value: "\(estimate.regressionEpisodes)")
                    StatRow(label: "Parallelism", value: estimate.parallelismLabel)
                } else {
                    Text("Estimate Compute Cost を実行すると、候補数・rollout数・episode数を確認できます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, KuyuSpacing.xs)
        } label: {
            Label("実行規模", systemImage: "ruler")
                .font(.headline)
        }
    }

    private var launchPolicy: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                StatRow(label: "Quality Gate", value: "strict")
                StatRow(label: "Task Pass Rate", value: "1.0 required")
                StatRow(label: "Checkpoint", value: "accepted only")
                StatRow(label: "Regression", value: "task profile")
            }
            .padding(.vertical, KuyuSpacing.xs)
        } label: {
            Label("受理ポリシー", systemImage: "checkmark.seal")
                .font(.headline)
        }
    }

    private func checklistRow(
        _ title: String,
        status: String,
        tone: StatusPill.Tone
    ) -> some View {
        HStack(spacing: KuyuSpacing.sm) {
            Image(systemName: tone == .success ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(tone == .success ? .green : .orange)
            Text(title)
                .font(.callout)
            Spacer(minLength: 0)
            StatusPill(status, tone: tone)
        }
    }

    private var readinessTone: StatusPill.Tone {
        switch model.learningCampaignReadiness.status {
        case .idle:
            return .warning
        case .ready:
            return .success
        case .blocked:
            return .danger
        }
    }

    private func compactPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "missing" }
        return URL(fileURLWithPath: trimmed).lastPathComponent
    }
}
