import KuyuTraining
import Logging
import SwiftUI

/// Workspace that attaches to training runs under the run root: a live run
/// list, per-run detail read from the run contract, and pause/resume/stop
/// control through the contract's file-based channel.
struct TrainingRunsWorkspaceView: View {
    @Bindable var model: TrainingRunsViewModel
    @State private var selectedGeneration: Int?
    @State private var selectedTestCaseID: String?
    @State private var selectedFailureGroupID: String?
    @State private var replayScenarioIdentity: String?
    @State private var isReplayPresented = false
    @State private var isEvidenceExpanded = false
    @State private var lastScrolledRunID: String?

    var body: some View {
        HSplitView {
            runList
                .frame(minWidth: 270, idealWidth: 310, maxWidth: 340)
            detailPane
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            await model.monitor()
        }
        .onChange(of: model.selectedRunID) { _, _ in
            resetDetailSelection()
            logRunSelection()
        }
        .sheet(isPresented: $isReplayPresented) {
            if let inspection = model.detail?.latestInspection {
                TrainingRunReplaySheetView(
                    artifact: inspection,
                    scenarioIdentity: replayScenarioIdentity
                )
            } else {
                ContentUnavailableView(
                    "Replay unavailable",
                    systemImage: "video.slash",
                    description: Text("This run does not reference a validated training-inspection artifact.")
                )
                .frame(minWidth: 720, minHeight: 480)
            }
        }
    }

    // MARK: - Run list

    private var runList: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: KuyuSpacing.sm) {
                Label("Training Runs", systemImage: "sidebar.left")
                    .font(.headline)
                Spacer(minLength: 0)
                Text(model.items.count.formatted())
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, KuyuSpacing.md)
            .padding(.vertical, KuyuSpacing.sm)

            if let error = model.lastError {
                errorBanner(error)
            }
            List(selection: $model.selectedRunID) {
                Section {
                    ForEach(model.items) { item in
                        TrainingRunRowView(item: item)
                            .tag(item.id)
                    }
                } header: {
                    Text(model.runRootPath ?? "run root unresolved")
                        .font(.system(.caption2, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.head)
                        .help(model.runRootPath ?? "Run root unresolved")
                }
            }
            .overlay {
                if model.items.isEmpty && model.lastError == nil {
                    ContentUnavailableView(
                        "No Training Runs",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Start one with `kuyu train`. Runs appear here as soon as their manifest is written.")
                    )
                }
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: KuyuSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.caption)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(KuyuSpacing.sm)
        .background(.yellow.opacity(0.12))
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailPane: some View {
        if let detail = model.detail {
            let learning = detail.learningProgress
            let testMatrix = detail.latestEvaluation.map(TrainingRunTestMatrixSnapshot.init)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: KuyuSpacing.lg) {
                        Color.clear
                            .frame(height: 0)
                            .id(detailTopID)
                        detailHeader(detail)
                        TrainingRunOverviewView(
                            detail: detail,
                            learning: learning,
                            testMatrix: testMatrix
                        )
                        TrainingRunLearningProgressView(
                            snapshot: learning,
                            selectedGeneration: $selectedGeneration
                        )
                        TrainingRunTestMatrixView(
                            snapshot: testMatrix,
                            inspection: detail.latestInspection,
                            selectedTestCaseID: $selectedTestCaseID,
                            openReplay: openReplay
                        )
                        TrainingRunFailureExplorerView(
                            snapshot: learning,
                            inspection: detail.latestInspection,
                            selectedRevision: selectedGeneration,
                            selectedFailureGroupID: $selectedFailureGroupID,
                            openReplay: openReplay,
                            restoreFailureExplorerPosition: {
                                proxy.scrollTo(failureExplorerID, anchor: .top)
                            }
                        )
                        .id(failureExplorerID)
                        TrainingRunEvidenceView(
                            detail: detail,
                            isExpanded: $isEvidenceExpanded
                        )
                    }
                    .padding(KuyuSpacing.lg)
                }
                .task(id: detail.runID) {
                    guard lastScrolledRunID != detail.runID else { return }
                    lastScrolledRunID = detail.runID
                    await Task.yield()
                    do {
                        try await Task.sleep(for: .milliseconds(100))
                    } catch {
                        return
                    }
                    proxy.scrollTo(detailTopID, anchor: .top)
                }
            }
            .onChange(of: selectedTestCaseID) { _, selectedID in
                synchronizeFailureSelection(
                    selectedTestCaseID: selectedID,
                    testMatrix: testMatrix,
                    learning: learning
                )
            }
        } else if model.isLoadingDetail {
            VStack(spacing: KuyuSpacing.md) {
                ProgressView()
                Text("Loading training run")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView(
                "No Run Selected",
                systemImage: "sidebar.left",
                description: Text("Select a run to inspect its manifest, journal, and control state.")
            )
        }
    }

    private var detailTopID: String {
        "training-run-detail-top"
    }

    private var failureExplorerID: String {
        "training-run-failure-explorer"
    }

    private func detailHeader(_ detail: TrainingRunDetailSnapshot) -> some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
            HStack(alignment: .center, spacing: KuyuSpacing.sm) {
                Text(detail.runID)
                    .font(.system(.headline, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(detail.runID)

                StatusPill(detail.liveness.displayLabel, tone: detail.liveness.pillTone)
                Spacer(minLength: KuyuSpacing.sm)

                HStack(spacing: KuyuSpacing.xs) {
                    Button { submit(.pause) } label: {
                        Image(systemName: "pause.fill")
                    }
                    .disabled(!canPause(detail.liveness))
                    .accessibilityLabel("Pause")
                    .help("Pause Training")

                    Button { submit(.resume) } label: {
                        Image(systemName: "play.fill")
                    }
                    .disabled(!canResume(detail.liveness))
                    .accessibilityLabel("Resume")
                    .help("Resume Training")

                    Button(role: .destructive) { submit(.stop) } label: {
                        Image(systemName: "stop.fill")
                    }
                    .disabled(!canStop(detail.liveness))
                    .accessibilityLabel("Stop")
                    .help("Stop Training")

                    if model.pendingControlSequence != nil {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack(alignment: .firstTextBaseline, spacing: KuyuSpacing.sm) {
                HStack(spacing: KuyuSpacing.sm) {
                    Text(detail.manifest.task)
                    Text(detail.latestEvaluation?.profileID ?? detail.manifest.profile)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer(minLength: KuyuSpacing.sm)
                if let refreshed = model.lastRefreshedAt {
                    Text("updated \(refreshed.formatted(date: .omitted, time: .standard))")
                }
                if let heartbeat = detail.heartbeat {
                    Text("attempt \(heartbeat.iteration + 1) / \(heartbeat.phase)")
                }
            }
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        .padding(.bottom, KuyuSpacing.sm)
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - Control gating

    private func openReplay(_ scenarioIdentity: String) {
        replayScenarioIdentity = scenarioIdentity
        isReplayPresented = true
    }

    private func resetDetailSelection() {
        selectedGeneration = nil
        selectedTestCaseID = nil
        selectedFailureGroupID = nil
        replayScenarioIdentity = nil
        isReplayPresented = false
        isEvidenceExpanded = false
        lastScrolledRunID = nil
    }

    private func synchronizeFailureSelection(
        selectedTestCaseID: String?,
        testMatrix: TrainingRunTestMatrixSnapshot?,
        learning: LearningProgressSnapshot
    ) {
        guard let selectedTestCaseID,
              let testCase = testMatrix?.testCases.first(where: { $0.id == selectedTestCaseID }),
              !testCase.passed,
              let group = learning.failureGroups.first(where: {
                  $0.scenario == testCase.scenarioID
                      && testCase.failureReasons.contains($0.reason)
              }) else {
            return
        }
        selectedGeneration = learning.currentGeneration
        selectedFailureGroupID = group.id
    }

    private func logRunSelection() {
        guard let selectedRunID = model.selectedRunID else { return }
        Logger(label: "kuyu.ui").info("Training run selected", metadata: [
            "action": "selectTrainingRun",
            "task": .string(model.detail?.manifest.task ?? "loading"),
            "runID": .string(selectedRunID),
        ])
    }

    private func submit(_ action: TrainingRunControlAction) {
        Logger(label: "kuyu.ui").info("Training run control submitted", metadata: [
            "action": .string(action.rawValue),
            "task": .string(model.detail?.manifest.task ?? "unknown"),
            "runID": .string(model.detail?.runID ?? "unknown"),
        ])
        Task { await model.submitControl(action) }
    }

    private func canPause(_ liveness: TrainingRunLiveness) -> Bool {
        if case .live = liveness { return true }
        return false
    }

    private func canResume(_ liveness: TrainingRunLiveness) -> Bool {
        if case .paused(processAlive: true) = liveness { return true }
        return false
    }

    private func canStop(_ liveness: TrainingRunLiveness) -> Bool {
        switch liveness {
        case .live, .paused(processAlive: true):
            return true
        case .finished, .interrupted, .paused:
            return false
        }
    }
}

#Preview {
    TrainingRunsWorkspaceView(model: TrainingRunsViewModel())
        .frame(width: 900, height: 600)
}
