import Foundation
import KuyuTraining
import Logging
import SwiftUI

struct TrainingRunTestMatrixView: View {
    let snapshot: TrainingRunTestMatrixSnapshot?
    let inspection: TrainingRunInspectionArtifact?
    @Binding var selectedTestCaseID: String?
    let openReplay: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: KuyuSpacing.sm) {
                Label("Evaluation Coverage", systemImage: "square.grid.3x3")
                    .font(.headline)
                Spacer(minLength: 0)
                if let snapshot {
                    Text("\(snapshot.passedCount) passed / \(snapshot.failedCount) failed / \(snapshot.testCases.count) cases")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            if let snapshot, !snapshot.testCases.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: KuyuSpacing.xl) {
                        matrix(snapshot)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        caseDetail(snapshot)
                            .frame(width: 360)
                    }
                    VStack(alignment: .leading, spacing: KuyuSpacing.md) {
                        matrix(snapshot)
                        caseDetail(snapshot)
                    }
                }
            } else {
                ContentUnavailableView(
                    "No typed evaluation matrix",
                    systemImage: "square.grid.3x3.topleft.filled",
                    description: Text("This run does not reference a validated checkpoint-evaluation artifact.")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            }
        }
        .padding(.vertical, KuyuSpacing.sm)
        .overlay(alignment: .bottom) { Divider() }
        .onAppear {
            selectInitialCaseIfNeeded()
        }
        .onChange(of: snapshot?.evaluationID) { _, _ in
            selectedTestCaseID = nil
            selectInitialCaseIfNeeded()
        }
    }

    private func matrix(_ snapshot: TrainingRunTestMatrixSnapshot) -> some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: KuyuSpacing.sm, verticalSpacing: KuyuSpacing.sm) {
                GridRow {
                    Text("Scenario")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 190, alignment: .leading)
                    ForEach(snapshot.seeds, id: \.self) { seed in
                        Text("seed \(seed)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 72)
                    }
                }

                Divider()
                    .gridCellColumns(snapshot.seeds.count + 1)

                ForEach(snapshot.scenarioIDs, id: \.self) { scenarioID in
                    GridRow {
                        Text(scenarioID)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(width: 190, alignment: .leading)
                            .help(scenarioID)
                        ForEach(snapshot.seeds, id: \.self) { seed in
                            testCell(snapshot.testCase(scenarioID: scenarioID, seed: seed))
                        }
                    }
                }
            }
            .padding(.vertical, KuyuSpacing.xs)
        }
    }

    @ViewBuilder
    private func testCell(_ testCase: TrainingRunTestMatrixSnapshot.TestCase?) -> some View {
        if let testCase {
            Button {
                selectedTestCaseID = testCase.id
                logTestCaseSelection(testCase)
            } label: {
                Image(systemName: testCase.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(testCase.passed ? Color.green : Color.red)
                    .frame(width: 72, height: 34)
                    .background(
                        selectedTestCaseID == testCase.id
                            ? Color.accentColor.opacity(0.14)
                            : Color.clear
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay {
                if selectedTestCaseID == testCase.id {
                    RoundedRectangle(cornerRadius: KuyuRadius.small)
                        .stroke(Color.accentColor, lineWidth: 1)
                }
            }
            .help("\(testCase.scenarioID), seed \(testCase.seed): \(testCase.passed ? "passed" : "failed")")
        } else {
            Image(systemName: "minus")
                .foregroundStyle(.tertiary)
                .frame(width: 72, height: 34)
                .help("Not evaluated")
        }
    }

    private func caseDetail(_ snapshot: TrainingRunTestMatrixSnapshot) -> some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
            Text("Selected case")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let testCase = selectedTestCase(snapshot) {
                HStack(alignment: .firstTextBaseline, spacing: KuyuSpacing.sm) {
                    Text(testCase.scenarioID)
                        .font(.system(.callout, design: .monospaced, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("seed \(testCase.seed)")
                        .font(.system(.caption, design: .monospaced))
                    Spacer(minLength: 0)
                    StatusPill(testCase.passed ? "PASS" : "FAIL", tone: testCase.passed ? .success : .danger)
                }

                casePair("Failure", failureSummary(testCase))
                casePair("Horizon", horizonSummary(testCase))
                casePair("Time step", timeStepSummary(testCase))
                casePair("Evaluation", snapshot.evaluationID)

                if replayScenario(for: testCase) != nil {
                    Button {
                        openReplay(testCase.id)
                        logReplayOpen(testCase)
                    } label: {
                        Label("Open Replay", systemImage: "play.rectangle")
                    }
                    .controlSize(.small)
                } else {
                    Label("Replay evidence was not recorded for this case", systemImage: "video.slash")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } else {
                Text("Select a matrix cell to inspect its result.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, KuyuSpacing.lg)
        .overlay(alignment: .leading) { Divider() }
    }

    private func casePair(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(3)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    private func selectedTestCase(
        _ snapshot: TrainingRunTestMatrixSnapshot
    ) -> TrainingRunTestMatrixSnapshot.TestCase? {
        if let selectedTestCaseID,
           let selected = snapshot.testCases.first(where: { $0.id == selectedTestCaseID }) {
            return selected
        }
        return snapshot.testCases.first(where: { !$0.passed }) ?? snapshot.testCases.first
    }

    private func replayScenario(
        for testCase: TrainingRunTestMatrixSnapshot.TestCase
    ) -> TrainingRunInspectionArtifact.Scenario? {
        inspection?.scenarios.first { $0.identity == testCase.id }
    }

    private func selectInitialCaseIfNeeded() {
        guard selectedTestCaseID == nil, let snapshot else { return }
        selectedTestCaseID = snapshot.testCases.first(where: { !$0.passed })?.id
            ?? snapshot.testCases.first?.id
    }

    private func failureSummary(_ testCase: TrainingRunTestMatrixSnapshot.TestCase) -> String {
        if testCase.failureReasons.isEmpty {
            return "None"
        }
        return testCase.failureReasons.joined(separator: ", ")
    }

    private func horizonSummary(_ testCase: TrainingRunTestMatrixSnapshot.TestCase) -> String {
        guard let duration = testCase.durationSeconds,
              let steps = testCase.stepCount else {
            return "Not recorded"
        }
        return String(format: "%.3g s / %@ steps", duration, steps.formatted())
    }

    private func timeStepSummary(_ testCase: TrainingRunTestMatrixSnapshot.TestCase) -> String {
        guard let timeStep = testCase.timeStepSeconds else { return "Not recorded" }
        return String(format: "%.6g s", timeStep)
    }

    private func logTestCaseSelection(_ testCase: TrainingRunTestMatrixSnapshot.TestCase) {
        Logger(label: "kuyu.ui").info("Training evaluation case selected", metadata: [
            "action": "selectEvaluationCase",
            "task": .string(snapshot?.task ?? "unknown"),
            "scenarioID": .string(testCase.scenarioID),
            "seed": .stringConvertible(testCase.seed),
        ])
    }

    private func logReplayOpen(_ testCase: TrainingRunTestMatrixSnapshot.TestCase) {
        Logger(label: "kuyu.ui").info("Training evaluation replay opened", metadata: [
            "action": "openEvaluationReplay",
            "task": .string(snapshot?.task ?? "unknown"),
            "scenarioID": .string(testCase.scenarioID),
            "seed": .stringConvertible(testCase.seed),
        ])
    }
}
