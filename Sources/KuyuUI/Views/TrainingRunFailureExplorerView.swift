import Charts
import Foundation
import KuyuTraining
import Logging
import SwiftUI

struct TrainingRunFailureExplorerView: View {
    private enum Scope: String, CaseIterable, Identifiable {
        case selectedRevision
        case entireRun

        var id: String { rawValue }
    }

    let snapshot: LearningProgressSnapshot
    let inspection: TrainingRunInspectionArtifact?
    let selectedRevision: Int?
    @Binding var selectedFailureGroupID: String?
    let openReplay: (String) -> Void
    let restoreFailureExplorerPosition: () -> Void

    @State private var scope: Scope = .selectedRevision

    var body: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: KuyuSpacing.sm) {
                Label("Failure Explorer", systemImage: "exclamationmark.magnifyingglass")
                    .font(.headline)
                Picker("Failure scope", selection: $scope) {
                    Text(selectedRevision.map { "Rev \($0)" } ?? "Selected revision")
                        .tag(Scope.selectedRevision)
                    Text("Entire run")
                        .tag(Scope.entireRun)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
                Spacer(minLength: 0)
                Text("\(scopedObservations.count) observations / \(scopedFailureGroups.count) groups")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if scopedFailureGroups.isEmpty {
                ContentUnavailableView(
                    "No failures in this scope",
                    systemImage: "checkmark.circle",
                    description: Text("Choose Entire run to inspect failures from other policy revisions.")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: KuyuSpacing.xl) {
                        failureGroupList
                            .frame(width: 390)
                            .frame(minHeight: 360)
                        selectedFailureDetail
                            .frame(maxWidth: .infinity, minHeight: 360, alignment: .topLeading)
                    }
                    VStack(alignment: .leading, spacing: KuyuSpacing.md) {
                        failureGroupList
                            .frame(minHeight: 260)
                        selectedFailureDetail
                    }
                }
            }
        }
        .padding(.vertical, KuyuSpacing.sm)
        .overlay(alignment: .bottom) { Divider() }
        .onAppear {
            selectInitialGroupIfNeeded()
        }
        .onChange(of: scopedFailureGroups.map(\.id)) { _, _ in
            selectInitialGroupIfNeeded()
        }
        .onChange(of: selectedRevision) { _, _ in
            if scope == .selectedRevision {
                selectedFailureGroupID = nil
                selectInitialGroupIfNeeded()
            }
        }
        .onChange(of: scope) { _, _ in
            selectedFailureGroupID = nil
            selectInitialGroupIfNeeded()
            logScopeSelection()
            restoreFailureExplorerPosition()
        }
        .onChange(of: selectedFailureGroupID) { _, selectedID in
            guard let selectedID,
                  let group = scopedFailureGroups.first(where: { $0.id == selectedID }) else {
                return
            }
            logFailureSelection(group)
        }
    }

    private var failureGroupList: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
            Text("Grouped by scenario and reason")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            List(scopedFailureGroups, selection: $selectedFailureGroupID) { group in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: KuyuSpacing.sm) {
                        Text(group.scenario)
                            .font(.system(.caption, design: .monospaced, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                        Text(group.observationCount.formatted())
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.red)
                    }
                    Text(group.reason)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                    Text("seeds \(group.seeds.count) / attempts \(group.firstAttempt)-\(group.lastAttempt)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .tag(group.id)
            }
        }
    }

    @ViewBuilder
    private var selectedFailureDetail: some View {
        if let group = selectedGroup {
            VStack(alignment: .leading, spacing: KuyuSpacing.md) {
                HStack(alignment: .firstTextBaseline, spacing: KuyuSpacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.scenario)
                            .font(.system(.title3, design: .monospaced, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(group.reason)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 0)
                    StatusPill("\(group.observationCount) observations", tone: .danger)
                }

                HStack(alignment: .top, spacing: 0) {
                    failureSignal("Seeds", group.seeds.map(String.init).joined(separator: ", "))
                    signalDivider
                    failureSignal("Attempt range", "\(group.firstAttempt)-\(group.lastAttempt)")
                    signalDivider
                    failureSignal("Latest revision", "\(group.latestGeneration)")
                    signalDivider
                    failureSignal("Latest terminal", "step \(group.latestTerminalStep)")
                }

                failureTrend(group)

                latestObservations(group)

                HStack(alignment: .top, spacing: KuyuSpacing.sm) {
                    if let replayIdentity = replayIdentity(for: group) {
                        Button {
                            openReplay(replayIdentity)
                            logReplayOpen(group, identity: replayIdentity)
                        } label: {
                            Label("Open Matching Replay", systemImage: "play.rectangle")
                        }
                        .controlSize(.small)
                    } else {
                        Label("No matching replay artifact was recorded", systemImage: "video.slash")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Spacer(minLength: 0)
                    Text("Journal observations do not identify rollout source or horizon; repeated cases remain separate evidence.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 420, alignment: .trailing)
                }
            }
            .padding(.leading, KuyuSpacing.lg)
            .overlay(alignment: .leading) { Divider() }
        }
    }

    private func failureTrend(_ group: LearningProgressSnapshot.FailureGroup) -> some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
            HStack {
                Text("Earliest terminal step by attempt")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                Text("lower means earlier failure")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Chart(failureTrendSamples(group)) { sample in
                LineMark(
                    x: .value("Attempt", Double(sample.attempt)),
                    y: .value("Terminal step", sample.terminalStep)
                )
                .foregroundStyle(Color.red)
                .interpolationMethod(.linear)
                PointMark(
                    x: .value("Attempt", Double(sample.attempt)),
                    y: .value("Terminal step", sample.terminalStep)
                )
                .foregroundStyle(Color.red)
                .symbolSize(14)
            }
            .chartXScale(
                domain: Double(group.firstAttempt)...Double(max(group.firstAttempt, group.lastAttempt))
            )
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4))
            }
            .chartPlotStyle { plot in
                plot.background(.quaternary.opacity(0.10))
            }
            .frame(minHeight: 150)
        }
    }

    private func latestObservations(_ group: LearningProgressSnapshot.FailureGroup) -> some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
            Text("Latest observations")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: KuyuSpacing.md, verticalSpacing: 3) {
                GridRow {
                    tableHeader("Attempt")
                    tableHeader("Rev")
                    tableHeader("Seed")
                    tableHeader("Terminal")
                }
                ForEach(Array(group.observations.suffix(8).reversed())) { observation in
                    GridRow {
                        tableValue(observation.attempt.formatted())
                        tableValue(observation.generation.formatted())
                        tableValue(observation.seed.formatted())
                        tableValue(observation.terminalStep.formatted())
                    }
                }
            }
        }
    }

    private func failureSignal(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var signalDivider: some View {
        Divider()
            .padding(.horizontal, KuyuSpacing.md)
    }

    private func tableHeader(_ value: String) -> some View {
        Text(value)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(minWidth: 64, alignment: .leading)
    }

    private func tableValue(_ value: String) -> some View {
        Text(value)
            .font(.system(.caption2, design: .monospaced))
            .monospacedDigit()
            .frame(minWidth: 64, alignment: .leading)
    }

    private var selectedGroup: LearningProgressSnapshot.FailureGroup? {
        if let selectedFailureGroupID,
           let selected = scopedFailureGroups.first(where: { $0.id == selectedFailureGroupID }) {
            return selected
        }
        return scopedFailureGroups.first
    }

    private var scopedRevision: Int? {
        scope == .selectedRevision ? selectedRevision : nil
    }

    private var scopedObservations: [LearningProgressSnapshot.FailureObservation] {
        snapshot.failureObservations(forRevision: scopedRevision)
    }

    private var scopedFailureGroups: [LearningProgressSnapshot.FailureGroup] {
        snapshot.failureGroups(forRevision: scopedRevision)
    }

    private func failureTrendSamples(
        _ group: LearningProgressSnapshot.FailureGroup
    ) -> [FailureTrendSample] {
        Dictionary(grouping: group.observations, by: \.attempt)
            .compactMap { attempt, observations in
                observations.map(\.terminalStep).min().map {
                    FailureTrendSample(attempt: attempt, terminalStep: $0)
                }
            }
            .sorted { $0.attempt < $1.attempt }
    }

    private func replayIdentity(
        for group: LearningProgressSnapshot.FailureGroup
    ) -> String? {
        guard let inspection,
              let inspectionIteration = inspection.iteration,
              let inspectionAttempt = snapshot.attempts.first(where: {
                  $0.id == inspectionIteration + 1
              }) else {
            return nil
        }
        if scope == .selectedRevision,
           let selectedRevision,
           inspectionAttempt.generation != selectedRevision {
            return nil
        }
        for observation in group.observations.reversed() {
            let identity = "\(observation.scenario)#\(observation.seed)"
            if inspection.scenarios.contains(where: { $0.identity == identity }) {
                return identity
            }
        }
        return nil
    }

    private func selectInitialGroupIfNeeded() {
        guard selectedFailureGroupID == nil
                || !scopedFailureGroups.contains(where: { $0.id == selectedFailureGroupID }) else {
            return
        }
        selectedFailureGroupID = scopedFailureGroups.first?.id
    }

    private func logFailureSelection(_ group: LearningProgressSnapshot.FailureGroup) {
        Logger(label: "kuyu.ui").info("Training failure group selected", metadata: [
            "action": "selectTrainingFailureGroup",
            "task": "trainingRun",
            "scenarioID": .string(group.scenario),
            "reason": .string(group.reason),
            "observationCount": .stringConvertible(group.observationCount),
            "revision": .stringConvertible(scopedRevision ?? -1),
        ])
    }

    private func logScopeSelection() {
        Logger(label: "kuyu.ui").info("Training failure scope selected", metadata: [
            "action": "selectTrainingFailureScope",
            "task": "trainingRun",
            "scope": .string(scope.rawValue),
            "revision": .stringConvertible(scopedRevision ?? -1),
        ])
    }

    private func logReplayOpen(
        _ group: LearningProgressSnapshot.FailureGroup,
        identity: String
    ) {
        Logger(label: "kuyu.ui").info("Training failure replay opened", metadata: [
            "action": "openTrainingFailureReplay",
            "task": "trainingRun",
            "scenarioID": .string(group.scenario),
            "replayIdentity": .string(identity),
        ])
    }
}

private struct FailureTrendSample: Identifiable {
    let attempt: Int
    let terminalStep: Int

    var id: Int { attempt }
}
