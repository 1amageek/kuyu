import SwiftUI

struct RunListView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: KuyuSpacing.md, verticalSpacing: KuyuSpacing.sm) {
            header
            Divider()
            if model.runs.isEmpty {
                GridRow {
                    Text("No runs yet")
                        .foregroundStyle(.secondary)
                        .gridCellColumns(8)
                }
            } else {
                ForEach(model.runs) { run in
                    GridRow {
                        Button(run.id.uuidString.prefix(8).description) {
                            model.selectedRunID = run.id
                        }
                        .buttonStyle(.plain)
                        StatusPill(run.output.summary.suitePassed ? "passed" : "failed", tone: run.output.summary.suitePassed ? .success : .danger)
                        Text(model.taskMode.rawValue)
                        Text(model.controllerSelection.rawValue)
                        Text(run.output.summary.suitePassed ? "1.00" : "0.00")
                            .font(.system(.caption, design: .monospaced))
                        Text("--")
                        Text("\(run.scenarios.count)")
                            .font(.system(.caption, design: .monospaced))
                        Text(run.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        GridRow {
            Text("Run ID")
            Text("Status")
            Text("Experiment")
            Text("Algorithm")
            Text("Reward")
            Text("Fitness")
            Text("Episodes")
            Text("Updated")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }
}
