import SwiftUI

struct InspectorView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ConfigPanelView(model: model)
            }
            .padding(12)
        }
        .background(KuyuUITheme.panelBackground)
    }
}

#Preview {
    InspectorView(model: KuyuUIPreviewFactory.model())
        .frame(width: 300, height: 700)
        .background(KuyuUITheme.background)
}
