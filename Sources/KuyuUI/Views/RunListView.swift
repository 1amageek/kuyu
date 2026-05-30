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
                        .fontWeight(run.id == model.selectedRunID ? .bold : .regular)
                        StatusPill(run.output.summary.suitePassed ? "passed" : "failed", tone: run.output.summary.suitePassed ? .success : .danger)
                        Text(passRate(run))
                            .font(.system(.caption, design: .monospaced))
                        Text(overshoot(run))
                            .font(.system(.caption, design: .monospaced))
                        Text(recovery(run))
                            .font(.system(.caption, design: .monospaced))
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
            Text("Pass")
            Text("Overshoot")
            Text("Recovery")
            Text("Scenarios")
            Text("Updated")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    /// Passed-scenario count over total, from the run's own evaluations.
    private func passRate(_ run: RunRecord) -> String {
        let evaluations = run.output.summary.evaluations
        guard !evaluations.isEmpty else { return "--" }
        let passed = evaluations.filter(\.passed).count
        return "\(passed)/\(evaluations.count)"
    }

    private func overshoot(_ run: RunRecord) -> String {
        guard let value = run.output.summary.aggregate.worstOvershootDegrees else { return "--" }
        return String(format: "%.1f°", value)
    }

    private func recovery(_ run: RunRecord) -> String {
        guard let value = run.output.summary.aggregate.averageRecoveryTime else { return "--" }
        return String(format: "%.2fs", value)
    }
}
