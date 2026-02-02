import SwiftUI

struct SidebarView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        List(selection: $model.selectedRunID) {
            Section("Suite") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("KUY-ATT-1")
                        .font(KuyuUITheme.titleFont(size: 14))
                        .foregroundStyle(KuyuUITheme.textPrimary)
                    Text("Attitude stability validation")
                        .font(KuyuUITheme.bodyFont(size: 12))
                        .foregroundStyle(KuyuUITheme.textSecondary)
                }
                .padding(.vertical, 6)
            }

            Section("Runs") {
                if model.runs.isEmpty {
                    Text("No runs yet")
                        .font(KuyuUITheme.bodyFont(size: 12))
                        .foregroundStyle(KuyuUITheme.textSecondary)
                } else {
                    ForEach(model.runs) { run in
                        RunRowView(run: run)
                            .tag(run.id)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(KuyuUITheme.panelBackground)
    }
}

#Preview {
    SidebarView(model: KuyuUIPreviewFactory.model())
        .frame(width: 280, height: 600)
}
