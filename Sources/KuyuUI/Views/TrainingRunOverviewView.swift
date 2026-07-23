import Foundation
import KuyuTraining
import SwiftUI

struct TrainingRunOverviewView: View {
    let detail: TrainingRunDetailSnapshot
    let learning: LearningProgressSnapshot
    let testMatrix: TrainingRunTestMatrixSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: KuyuSpacing.sm) {
                Label("Run Overview", systemImage: "rectangle.3.group")
                    .font(.headline)
                Spacer(minLength: 0)
                if let evaluation = detail.latestEvaluation {
                    StatusPill(
                        evaluation.policyPassed ? "evaluation passed" : "evaluation failed",
                        tone: evaluation.policyPassed ? .success : .danger
                    )
                } else {
                    StatusPill("evaluation unavailable", tone: .warning)
                }
            }

            HStack(alignment: .top, spacing: 0) {
                overviewColumn(
                    title: "Platform",
                    systemImage: platformSystemImage
                ) {
                    overviewValue(platformFamilyLabel, emphasis: true)
                    overviewPair("Robot manifest", robotManifestLabel)
                    if let inspection = detail.latestInspection {
                        overviewPair(
                            "Mass / arm",
                            String(
                                format: "%.3g kg / %.3g m",
                                inspection.execution.parameters.mass,
                                inspection.execution.parameters.armLength
                            )
                        )
                        overviewPair(
                            "Motor limit",
                            String(
                                format: "%.3g N / %.3g s",
                                inspection.execution.parameters.maxThrust,
                                inspection.execution.parameters.motorTimeConstant
                            )
                        )
                    } else {
                        missingEvidence("Physical parameters were not recorded")
                    }
                }

                Divider()
                    .padding(.horizontal, KuyuSpacing.lg)

                overviewColumn(
                    title: "Evaluation Plan",
                    systemImage: "checklist"
                ) {
                    overviewValue(testPlanSummary, emphasis: true)
                    overviewPair("Profile", profileLabel)
                    overviewPair("Suites", suiteSummary)
                    overviewPair("Horizon", evaluationHorizonSummary)
                }

                Divider()
                    .padding(.horizontal, KuyuSpacing.lg)

                overviewColumn(
                    title: "Current Progress",
                    systemImage: "chart.line.uptrend.xyaxis"
                ) {
                    overviewValue(progressSummary, emphasis: true)
                    overviewPair("Generation lineage", generationLineageSummary)
                    overviewPair("Attempts", learning.attempts.count.formatted())
                    overviewPair("Since accepted", attemptsSinceAcceptedSummary)
                    overviewPair("Latest gate", evaluationGateSummary)
                }
            }

            if let ratio = learning.supportCompletionRatio {
                VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
                    HStack {
                        Text("Curriculum support")
                        Spacer(minLength: 0)
                        Text(horizonProgressSummary)
                            .monospacedDigit()
                    }
                    .font(.caption)
                    ProgressView(value: ratio, total: 1)
                        .tint(ratio >= 1 ? .green : .cyan)
                }
            }

            if let evaluation = detail.latestEvaluation, !evaluation.policyPassed {
                HStack(alignment: .top, spacing: KuyuSpacing.sm) {
                    Image(systemName: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("The retained policy is not release-ready")
                            .font(.callout.weight(.semibold))
                        Text(evaluationFailureSummary(evaluation))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, KuyuSpacing.sm)
                .overlay(alignment: .top) { Divider() }
            }
        }
        .padding(.vertical, KuyuSpacing.sm)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func overviewColumn<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func overviewValue(_ value: String, emphasis: Bool) -> some View {
        Text(value)
            .font(emphasis ? .title3.weight(.semibold) : .callout)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
    }

    private func overviewPair(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    private func missingEvidence(_ value: String) -> some View {
        Label(value, systemImage: "exclamationmark.triangle")
            .font(.caption2)
            .foregroundStyle(.orange)
    }

    private var platformFamilyLabel: String {
        switch detail.evaluationProfile?.family {
        case .referenceQuadrotor:
            return "Reference quadrotor"
        case .roArmM1ArmGripper:
            return "RoArm-M1 arm + gripper"
        case nil:
            return "Not recorded"
        }
    }

    private var platformSystemImage: String {
        switch detail.evaluationProfile?.family {
        case .referenceQuadrotor:
            return "move.3d"
        case .roArmM1ArmGripper:
            return "hand.raised.fingers.spread"
        case nil:
            return "questionmark.square.dashed"
        }
    }

    private var robotManifestLabel: String {
        detail.latestInspection?.execution.robotManifestID ?? "Not recorded"
    }

    private var testPlanSummary: String {
        guard let testMatrix else { return "No typed test matrix" }
        return "\(testMatrix.scenarioIDs.count) scenarios x \(testMatrix.seeds.count) seeds"
    }

    private var profileLabel: String {
        detail.latestEvaluation?.profileID ?? detail.manifest.profile
    }

    private var suiteSummary: String {
        guard let profile = detail.evaluationProfile else { return "Not recorded" }
        let base = profile.baseEvaluationSuiteIDs.map(String.init).joined(separator: ",")
        let regression = profile.regressionSuiteIDs.map(String.init).joined(separator: ",")
        return "base [\(base)] / regression [\(regression)]"
    }

    private var evaluationHorizonSummary: String {
        guard let testMatrix,
              let first = testMatrix.testCases.first,
              let duration = first.durationSeconds,
              let stepCount = first.stepCount else {
            return "Not recorded"
        }
        return String(format: "%.3g s / %@ steps", duration, stepCount.formatted())
    }

    private var progressSummary: String {
        if learning.hasGenerationLineage {
            return "Policy revision \(learning.currentGeneration)"
        }
        return "\(learning.attempts.count) training attempts"
    }

    private var generationLineageSummary: String {
        learning.hasGenerationLineage
            ? "\(learning.decisionRecordedCount) decisions recorded"
            : "Not recorded by this run contract"
    }

    private var attemptsSinceAcceptedSummary: String {
        guard learning.hasGenerationLineage else {
            return "Not recorded"
        }
        guard let attempts = learning.attemptsSinceLastAccepted else {
            return "No accepted update"
        }
        return "\(attempts) attempts"
    }

    private var evaluationGateSummary: String {
        guard let passed = detail.latestEvaluation?.policyPassed else { return "Not recorded" }
        return passed ? "PASS" : "FAIL"
    }

    private var horizonProgressSummary: String {
        guard let current = learning.currentSupportHorizon,
              let full = learning.fullHorizon,
              let ratio = learning.supportCompletionRatio else {
            return "Not recorded"
        }
        return "\(current.formatted()) / \(full.formatted()) (\(ratio.formatted(.percent.precision(.fractionLength(1)))))"
    }

    private func evaluationFailureSummary(_ evaluation: CheckpointEvaluationArtifact) -> String {
        let reasons = evaluation.failureReasons.isEmpty
            ? "No failure reason recorded"
            : evaluation.failureReasons.joined(separator: ", ")
        return "Latest evaluation: \(reasons). Capability progress and release readiness are separate judgments."
    }
}
