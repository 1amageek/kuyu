import SwiftUI

struct ResultsWorkspaceView: View {
    @Bindable var model: AppViewModel
    @State private var scope: Scope = .session

    private enum Scope: String, CaseIterable, Identifiable {
        case session
        case archive

        var id: String { rawValue }

        var title: String {
            switch self {
            case .session: return "Session"
            case .archive: return "Archive"
            }
        }
    }

    private var resultsModel: SimulationViewModel {
        model.simulationViewModel
    }

    var body: some View {
        VStack(spacing: 0) {
            scopePicker
            Divider()
            switch scope {
            case .session:
                sessionResults
            case .archive:
                TrainingRunsWorkspaceView(model: model.trainingRunsViewModel)
            }
        }
    }

    private var scopePicker: some View {
        HStack {
            Picker("Scope", selection: $scope) {
                ForEach(Scope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 280)
            Spacer()
        }
        .padding(KuyuSpacing.sm)
    }

    @ViewBuilder
    private var sessionResults: some View {
        if resultsModel.runs.isEmpty {
            ContentUnavailableView(
                "No runs yet",
                systemImage: "tray",
                description: Text("Launch a campaign or baseline from the Run workspace to inspect results here.")
            )
        } else {
            HSplitView {
                runList
                    .frame(minWidth: 220, maxWidth: 320)
                RunDetailView(model: resultsModel)
                    .frame(minWidth: 240, maxWidth: 380)
                ScenarioDetailView(model: resultsModel)
                    .frame(minWidth: 460, maxWidth: .infinity)
            }
            .onChange(of: resultsModel.selectedRunID) { _, _ in
                // Reset scenario selection so the detail defaults to the new run's first scenario.
                resultsModel.selectedScenarioKey = nil
            }
        }
    }

    private var runList: some View {
        List(selection: Bindable(resultsModel).selectedRunID) {
            ForEach(resultsModel.runs) { run in
                RunRowView(run: run)
                    .tag(run.id as UUID?)
            }
        }
    }
}
