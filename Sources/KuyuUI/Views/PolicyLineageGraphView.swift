import SwiftUI
import KuyuMLXCampaignContracts

struct PolicyLineageGraphView: View {
    let state: LearningCampaignRunStoreState?

    private var rows: [LearningCampaignGenerationState] {
        guard let state else { return [] }
        return Array(state.latestGenerations.prefix(36)).reversed()
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.md) {
                ZStack {
                    Canvas { context, size in
                        drawGraph(context: &context, size: size)
                    }
                    .frame(minHeight: 220)

                    if rows.isEmpty {
                        Text("No lineage data yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: KuyuSpacing.md) {
                    legend("incumbent", color: .secondary)
                    legend("improved", color: .cyan)
                    legend("accepted", color: .green)
                    Spacer(minLength: 0)
                }
                .font(.caption)
            }
        } label: {
            Label("Policy Lineage", systemImage: "point.3.filled.connected.trianglepath.dotted")
        }
        .frame(maxWidth: .infinity)
    }

    private func drawGraph(context: inout GraphicsContext, size: CGSize) {
        guard !rows.isEmpty else { return }
        let count = max(rows.count, 1)
        let horizontalStep = size.width / CGFloat(max(count - 1, 1))
        let midY = size.height * 0.52
        var points: [CGPoint] = []

        for (index, row) in rows.enumerated() {
            let x = CGFloat(index) * horizontalStep
            let delta = row.bestVsIncumbentDelta ?? 0
            let clamped = min(max(delta, -1), 1)
            let y = midY - CGFloat(clamped) * size.height * 0.28
            points.append(CGPoint(x: x, y: y))
        }

        var path = Path()
        if let first = points.first {
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
        }
        context.stroke(path, with: .color(.cyan.opacity(0.65)), lineWidth: 2)

        for (index, row) in rows.enumerated() {
            let point = points[index]
            let color: Color = row.accepted ? .green : (row.incumbentImproved ? .cyan : .secondary)
            let radius: CGFloat = row.accepted ? 7 : 5
            let rect = CGRect(
                x: point.x - radius,
                y: point.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.95)))
            context.stroke(Path(ellipseIn: rect.insetBy(dx: -2, dy: -2)), with: .color(color.opacity(0.24)), lineWidth: 4)
        }
    }

    private func legend(_ label: String, color: Color) -> some View {
        HStack(spacing: KuyuSpacing.xs) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .foregroundStyle(.secondary)
        }
    }
}
