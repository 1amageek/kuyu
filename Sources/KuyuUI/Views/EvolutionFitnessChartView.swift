import Charts
import SwiftUI

struct EvolutionFitnessChartView: View {
    let state: LearningCampaignRunStoreState?

    private var generations: [LearningCampaignGenerationState] {
        guard let state else { return [] }
        return state.generations.sorted { lhs, rhs in
            if lhs.generationIndex != rhs.generationIndex {
                return lhs.generationIndex < rhs.generationIndex
            }
            return lhs.seed < rhs.seed
        }
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.md) {
                if generations.isEmpty {
                    placeholder
                } else {
                    Chart {
                        ForEach(generations, id: \.id) { row in
                            if let best = row.bestFitness {
                                LineMark(
                                    x: .value("Generation", row.generationIndex),
                                    y: .value("Best fitness", best)
                                )
                                .foregroundStyle(.purple)
                                .symbol(row.accepted ? .circle : .square)
                            }
                            if let incumbent = row.incumbentFitness {
                                LineMark(
                                    x: .value("Generation", row.generationIndex),
                                    y: .value("Incumbent", incumbent)
                                )
                                .foregroundStyle(.cyan.opacity(0.8))
                                .lineStyle(StrokeStyle(lineWidth: 1.4, dash: [5, 4]))
                            }
                        }
                    }
                    .chartXAxisLabel("generation")
                    .chartYAxisLabel("fitness")
                    .chartLegend(.hidden)
                    .frame(minHeight: 250)
                }
            }
        } label: {
            HStack {
                Label("Genetic Learning", systemImage: "point.3.connected.trianglepath.dotted")
                Spacer()
                if let best = generations.compactMap(\.bestFitness).max() {
                    Text(String(format: "%.2f", best))
                        .font(.system(.callout, design: .monospaced).weight(.semibold))
                        .foregroundStyle(.purple)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: KuyuRadius.medium, style: .continuous)
                .fill(.quaternary)
            Text("No generation artifacts yet")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minHeight: 250)
    }
}
