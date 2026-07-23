import Charts
import Foundation
import KuyuTraining
import SwiftUI

struct TrainingRunLearningProgressView: View {
    let snapshot: LearningProgressSnapshot
    @Binding var selectedGeneration: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: KuyuSpacing.sm) {
                Label("Learning Progress", systemImage: "chart.xyaxis.line")
                    .font(.headline)
                Spacer(minLength: 0)
                Text(progressHeaderSummary)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            progressSignals

            Label(
                "Retained revisions passed the non-regression gate. Qualified improvements also contain a material before/after signal.",
                systemImage: "info.circle"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: KuyuSpacing.lg) {
                    capabilityChart
                        .frame(minWidth: 560, maxWidth: .infinity)
                    generationTable
                        .frame(width: 470)
                }
                VStack(alignment: .leading, spacing: KuyuSpacing.md) {
                    capabilityChart
                    generationTable
                        .frame(minHeight: 300)
                }
            }

            selectedGenerationSummary

            Label("Metrics by training attempt", systemImage: "chart.line.uptrend.xyaxis")
                .font(.subheadline.weight(.semibold))

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 180), spacing: KuyuSpacing.lg)],
                alignment: .leading,
                spacing: KuyuSpacing.lg
            ) {
                attemptMetricChart(
                    title: "Evaluation score",
                    unit: "score",
                    color: .blue,
                    samples: attemptSamples(\.evaluationScore)
                )
                attemptMetricChart(
                    title: "Training loss",
                    unit: "loss",
                    color: .purple,
                    samples: attemptSamples(\.trainingLoss)
                )
                attemptMetricChart(
                    title: "Failure rate",
                    unit: "%",
                    color: .red,
                    samples: attemptSamples { $0.failureRate.map { $0 * 100 } }
                )
                attemptMetricChart(
                    title: "Maximum angular rate",
                    unit: "rad/s",
                    color: .orange,
                    samples: attemptSamples(\.maximumAngularRate)
                )
                attemptMetricChart(
                    title: "Reward / step",
                    unit: "normalized",
                    color: .green,
                    samples: attemptSamples(\.rewardPerStep)
                )
            }
        }
        .padding(.vertical, KuyuSpacing.sm)
        .overlay(alignment: .bottom) { Divider() }
        .onAppear {
            selectCurrentGenerationIfNeeded()
        }
        .onChange(of: snapshot.currentGeneration) { _, _ in
            selectCurrentGenerationIfNeeded()
        }
    }

    private var progressSignals: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 116), spacing: KuyuSpacing.md)],
            alignment: .leading,
            spacing: KuyuSpacing.md
        ) {
            progressSignal(
                title: "Curriculum",
                value: snapshot.supportCompletionRatio.map(percent) ?? "--",
                detail: horizonSummary,
                color: .cyan
            )
            progressSignal(
                title: "Policy revision",
                value: snapshot.hasGenerationLineage ? "\(snapshot.currentGeneration)" : "--",
                detail: snapshot.hasGenerationLineage ? "retained policy" : "lineage not recorded",
                color: .primary
            )
            progressSignal(
                title: "Last improvement",
                value: snapshot.hasGenerationLineage ? attemptsSinceImprovementValue : "--",
                detail: snapshot.hasGenerationLineage ? "attempts ago" : "decision not recorded",
                color: attemptsSinceImprovementColor
            )
            progressSignal(
                title: "Latest score",
                value: latestScoreValue,
                detail: latestScoreDetail,
                color: latestScoreColor
            )
            progressSignal(
                title: "Evaluation gate",
                value: evaluationValue,
                detail: evaluationDetail,
                color: evaluationColor
            )
            progressSignal(
                title: "Failures",
                value: snapshot.attempts.last?.failureRate.map(percent) ?? "--",
                detail: "latest attempt",
                color: .red
            )
        }
        .padding(.vertical, KuyuSpacing.sm)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
    }

    private var capabilityChart: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Retained capability over attempts")
                        .font(.subheadline.weight(.semibold))
                    Text("Line: supported horizon. Green: qualified improvement. Orange: retained only.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text("steps")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if snapshot.attempts.isEmpty {
                ContentUnavailableView(
                    "Waiting for the first attempt",
                    systemImage: "hourglass",
                    description: Text("The run exists, but no iteration has been journaled yet.")
                )
                .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                Chart {
                    ForEach(snapshot.attempts) { attempt in
                        if let horizon = attempt.supportHorizon {
                            LineMark(
                                x: .value("Attempt", attempt.id),
                                y: .value("Supported horizon", horizon)
                            )
                            .foregroundStyle(Color.cyan)
                            .interpolationMethod(.stepEnd)
                        }
                        if attempt.accepted, let horizon = attempt.supportHorizon {
                            PointMark(
                                x: .value("Attempt", attempt.id),
                                y: .value("Accepted update", horizon)
                            )
                            .foregroundStyle(attempt.materiallyImproved ? Color.green : Color.orange)
                            .symbolSize(34)
                        }
                    }

                    if let fullHorizon = snapshot.fullHorizon {
                        RuleMark(y: .value("Full horizon", fullHorizon))
                            .foregroundStyle(.secondary.opacity(0.7))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .annotation(position: .top, alignment: .trailing) {
                                Text("target \(fullHorizon.formatted())")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                    }

                    if let generation = selectedGenerationSnapshot {
                        RectangleMark(
                            xStart: .value("Generation start", generation.firstAttempt - 1),
                            xEnd: .value("Generation end", generation.lastAttempt),
                            yStart: .value("Selection floor", 0),
                            yEnd: .value("Selection ceiling", chartMaximumHorizon)
                        )
                        .foregroundStyle(Color.accentColor.opacity(0.07))

                        RuleMark(x: .value("Selected attempt", generation.lastAttempt))
                            .foregroundStyle(Color.accentColor.opacity(0.8))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                    }
                }
                .chartXScale(domain: 1...max(1, snapshot.attempts.count))
                .chartYScale(domain: 0...chartMaximumHorizon)
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 5))
                }
                .chartPlotStyle { plot in
                    plot.background(.quaternary.opacity(0.10))
                }
                .frame(minHeight: 300)
            }
        }
    }

    private var generationTable: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
            HStack {
                Text(snapshot.hasGenerationLineage ? "Retained policy revisions" : "Policy state (lineage unavailable)")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                Text("select for details")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Table(snapshot.generations, selection: $selectedGeneration) {
                TableColumn("Revision") { generation in
                    Text(generation.displayName)
                        .font(.system(.caption, design: .monospaced, weight: .medium))
                }
                .width(min: 68, ideal: 76)

                TableColumn("Attempts") { generation in
                    Text("\(generation.firstAttempt)-\(generation.lastAttempt)")
                        .monospacedDigit()
                }
                .width(min: 64, ideal: 74)

                TableColumn("Horizon") { generation in
                    Text(generation.bestSupportHorizon?.formatted() ?? "--")
                        .monospacedDigit()
                }
                .width(min: 64, ideal: 76)

                TableColumn("Failure") { generation in
                    Text(generation.latestAttempt.failureRate.map(percent) ?? "--")
                        .monospacedDigit()
                        .foregroundStyle(failureColor(generation.latestAttempt.failureRate))
                }
                .width(min: 58, ideal: 66)

                TableColumn("Gate") { generation in
                    gateLabel(generation.latestEvaluationPassed)
                }
                .width(min: 50, ideal: 58)
            }
            .frame(minHeight: 300)
        }
    }

    @ViewBuilder
    private var selectedGenerationSummary: some View {
        if let generation = selectedGenerationSnapshot {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
                    Text(generation.displayName)
                        .font(.title3.weight(.semibold))
                    Text(generationRangeSummary(generation))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 110), spacing: KuyuSpacing.lg)],
                    alignment: .leading,
                    spacing: KuyuSpacing.sm
                ) {
                    generationDetail("Supported", generation.bestSupportHorizon?.formatted() ?? "--", "steps")
                    generationDetail(
                        "Score",
                        generation.latestEvaluationScore.map { String(format: "%.3f", $0) } ?? "--",
                        generation.latestEvaluationAttempt.map { "attempt \($0)" } ?? "not evaluated"
                    )
                    generationDetail(
                        "Loss",
                        generation.latestAttempt.trainingLoss.map { String(format: "%.6f", $0) } ?? "--",
                        "latest"
                    )
                    generationDetail("Failure", generation.latestAttempt.failureRate.map(percent) ?? "--", "latest")
                    generationDetail(
                        "Max omega",
                        generation.latestAttempt.maximumAngularRate.map { String(format: "%.3f", $0) } ?? "--",
                        "rad/s"
                    )
                    generationDetail(
                        "Evaluation",
                        gateValue(generation.latestEvaluationPassed),
                        generation.latestEvaluationAttempt.map { "attempt \($0)" } ?? "not evaluated"
                    )
                }
                if let checkpoint = generation.checkpointPath {
                    Text(checkpoint)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .frame(maxWidth: 360, alignment: .leading)
                }
            }
            .padding(.vertical, KuyuSpacing.sm)
            .overlay(alignment: .top) { Divider() }
            .overlay(alignment: .bottom) { Divider() }
        }
    }

    private func attemptMetricChart(
        title: String,
        unit: String,
        color: Color,
        samples: [AttemptMetricSample]
    ) -> some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if samples.isEmpty {
                Text("Not recorded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 130)
            } else {
                Chart(samples) { sample in
                    LineMark(
                        x: .value("Attempt", sample.attempt),
                        y: .value(title, sample.value)
                    )
                    .foregroundStyle(color)
                    .interpolationMethod(.linear)
                    PointMark(
                        x: .value("Attempt", sample.attempt),
                        y: .value(title, sample.value)
                    )
                    .foregroundStyle(color)
                    .symbolSize(16)
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 4))
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4))
                }
                .chartPlotStyle { plot in
                    plot.background(.quaternary.opacity(0.10))
                }
                .frame(minHeight: 150)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func progressSignal(
        title: String,
        value: String,
        detail: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .monospaced, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func generationDetail(_ title: String, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.callout, design: .monospaced, weight: .semibold))
                .monospacedDigit()
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func attemptSamples(
        _ value: (LearningProgressSnapshot.Attempt) -> Double?
    ) -> [AttemptMetricSample] {
        snapshot.attempts.compactMap { attempt in
            value(attempt).map {
                AttemptMetricSample(attempt: attempt.id, value: $0)
            }
        }
    }

    private func selectCurrentGenerationIfNeeded() {
        guard selectedGeneration == nil
                || !snapshot.generations.contains(where: { $0.id == selectedGeneration }) else {
            return
        }
        selectedGeneration = snapshot.generations.last?.id
    }

    private var selectedGenerationSnapshot: LearningProgressSnapshot.Generation? {
        if let selectedGeneration,
           let selected = snapshot.generations.first(where: { $0.id == selectedGeneration }) {
            return selected
        }
        return snapshot.generations.last
    }

    private var chartMaximumHorizon: Double {
        let observed = snapshot.attempts.compactMap(\.supportHorizon).max() ?? 0
        return Double(max(1, max(observed, snapshot.fullHorizon ?? 0)))
    }

    private var horizonSummary: String {
        guard let current = snapshot.currentSupportHorizon,
              let full = snapshot.fullHorizon else {
            return "not recorded"
        }
        return "\(current.formatted()) / \(full.formatted()) steps"
    }

    private var attemptsSinceImprovementValue: String {
        snapshot.attemptsSinceLastMaterialImprovement.map(String.init) ?? "--"
    }

    private var attemptsSinceImprovementColor: Color {
        guard let attempts = snapshot.attemptsSinceLastMaterialImprovement else {
            return .secondary
        }
        return attempts == 0 ? .green : .orange
    }

    private var evaluationValue: String {
        gateValue(snapshot.latestEvaluationPassed)
    }

    private var evaluationDetail: String {
        guard let attempt = snapshot.latestEvaluationAttempt else { return "not evaluated" }
        if let score = snapshot.latestEvaluationScore {
            return "attempt \(attempt), score \(String(format: "%.3f", score))"
        }
        return "attempt \(attempt)"
    }

    private var latestScoreValue: String {
        snapshot.latestEvaluationScore.map { String(format: "%.3f", $0) } ?? "--"
    }

    private var latestScoreDetail: String {
        guard let attempt = snapshot.latestEvaluationAttempt else { return "not evaluated" }
        return "attempt \(attempt)"
    }

    private var latestScoreColor: Color {
        snapshot.latestEvaluationScore == nil ? .secondary : .blue
    }

    private var progressHeaderSummary: String {
        if snapshot.hasGenerationLineage {
            return "\(snapshot.attempts.count) attempts / \(snapshot.acceptedGenerationCount) retained / \(snapshot.materiallyImprovedGenerationCount) improved"
        }
        return "\(snapshot.attempts.count) attempts / generation lineage not recorded"
    }

    private var evaluationColor: Color {
        switch snapshot.latestEvaluationPassed {
        case true:
            return .green
        case false:
            return .red
        case nil:
            return .secondary
        }
    }

    private func generationRangeSummary(_ generation: LearningProgressSnapshot.Generation) -> String {
        if let acceptedAt = generation.acceptedAtAttempt {
            if let improvedAt = generation.materiallyImprovedAtAttempt {
                return "retained and improved at attempt \(improvedAt); observed through attempt \(generation.lastAttempt)"
            }
            return "retained at attempt \(acceptedAt), improvement not qualified; observed through attempt \(generation.lastAttempt)"
        }
        return "initial retained policy; observed through attempt \(generation.lastAttempt)"
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(1)))
    }

    private func failureColor(_ value: Double?) -> Color {
        guard let value else { return .secondary }
        return value == 0 ? .green : .red
    }

    private func gateValue(_ passed: Bool?) -> String {
        switch passed {
        case true:
            return "PASS"
        case false:
            return "FAIL"
        case nil:
            return "--"
        }
    }

    @ViewBuilder
    private func gateLabel(_ passed: Bool?) -> some View {
        switch passed {
        case true:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .help("Evaluation passed")
        case false:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .help("Evaluation failed")
        case nil:
            Image(systemName: "minus.circle")
                .foregroundStyle(.secondary)
                .help("No evaluation recorded for this generation")
        }
    }
}

private struct AttemptMetricSample: Identifiable {
    let attempt: Int
    let value: Double

    var id: Int { attempt }
}

#Preview("Learning progress") {
    TrainingRunLearningProgressView(
        snapshot: LearningProgressSnapshot.preview,
        selectedGeneration: .constant(2)
    )
    .frame(width: 980, height: 980)
    .padding()
}

private extension LearningProgressSnapshot {
    static let preview = LearningProgressSnapshot(records: [
        previewRecord(iteration: 0, horizon: 96, accepted: false, score: 0.21, loss: 1.24, failureRate: 0.42, passed: false),
        previewRecord(iteration: 1, horizon: 112, accepted: true, score: 0.46, loss: 0.88, failureRate: 0.28, passed: false, checkpointPath: "checkpoints/revision-1"),
        previewRecord(iteration: 2, horizon: 128, accepted: false, score: 0.41, loss: 0.76, failureRate: 0.31, passed: false, failureSeed: 17),
        previewRecord(iteration: 3, horizon: 160, accepted: true, score: 0.72, loss: 0.54, failureRate: 0.14, passed: true, checkpointPath: "checkpoints/revision-2"),
        previewRecord(iteration: 4, horizon: 184, accepted: false, score: 0.69, loss: 0.43, failureRate: 0.09, passed: true),
    ])

    private static func previewRecord(
        iteration: Int,
        horizon: Int,
        accepted: Bool,
        score: Double,
        loss: Double,
        failureRate: Double,
        passed: Bool,
        checkpointPath: String? = nil,
        failureSeed: UInt64? = nil
    ) -> TrainingRunIterationRecord {
        let failureEpisodes = failureSeed.map {
            [TrainingRunIterationRecord.FailureEpisode(
                scenario: "single-lift",
                seed: $0,
                terminalStep: max(1, horizon - 8),
                reason: "sustained-fall"
            )]
        } ?? []
        let checkpoint = checkpointPath.map {
            TrainingRunIterationRecord.CheckpointReference(
                path: $0,
                sha256Digest: String(repeating: "a", count: 64)
            )
        }
        return TrainingRunIterationRecord(
            iteration: iteration,
            recordedAt: Date(timeIntervalSince1970: Double(iteration)),
            horizon: TrainingRunIterationRecord.HorizonState(
                supportHorizon: horizon,
                frontierHorizon: min(horizon + 24, 200),
                fullHorizon: 200,
                mode: "supervised"
            ),
            decision: TrainingRunIterationRecord.CandidateDecision(
                accepted: accepted,
                materiallyImproved: accepted,
                rejectionReasons: accepted ? [] : ["candidate-regressed"],
                progressSignals: accepted ? ["reward-average-improved"] : [],
                progressRejectionReasons: accepted ? [] : ["candidate-not-retained"],
                horizonHealth: [
                    "failureRate": failureRate,
                    "failureCount": failureRate * 10,
                    "episodeCount": 10,
                    "maxOmega": 4.2 - Double(iteration) * 0.35,
                    "rewardAverage": -40 + Double(iteration) * 8,
                    "terminalStepAverage": 100,
                ]
            ),
            evaluation: TrainingRunIterationRecord.EvaluationRecord(
                evaluationHorizon: horizon,
                metrics: [
                    "score": score,
                    "suitePassed": passed ? 1 : 0,
                    "trainingLoss": loss,
                ]
            ),
            failureEpisodes: failureEpisodes,
            phaseTimings: ["iterationSeconds": 4.0 + Double(iteration)],
            checkpoint: checkpoint
        )
    }
}
