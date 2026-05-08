import SwiftUI

struct HybridIntegrationConfigView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.md) {
            GroupBox {
                VStack(alignment: .leading, spacing: KuyuSpacing.md) {
                    StatRow(label: "RL to GA Handoff", value: "Checkpoint Candidate")
                    StatRow(label: "GA to RL Handoff", value: "Accepted Elite")
                    IntegerStepperView(label: "Integration Interval", value: $model.learningCampaignGenerations, range: 1...10_000)
                    StatRow(label: "Policy Replacement", value: "Accepted Only")
                    StatRow(label: "Population Seeding", value: "enabled")
                    StatRow(label: "Quality Gate", value: "strict")
                }
            } label: {
                Label("Hybrid Integration", systemImage: "arrow.triangle.merge")
            }

            GroupBox {
                VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                    StatRow(label: "Fitness to Reward Mapping", value: "artifact evaluator")
                    StatRow(label: "Hybrid Schedule", value: "campaign generation")
                    StatRow(label: "Conflict Resolution", value: "checkpoint gate wins")
                }
            } label: {
                Label("Coupling", systemImage: "link")
            }
        }
    }
}
