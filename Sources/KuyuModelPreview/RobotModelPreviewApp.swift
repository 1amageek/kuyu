import KuyuUI
import SwiftUI

@main
struct RobotModelPreviewApp: App {
    var body: some Scene {
        Window("Robot Model Preview", id: "robot-model-preview") {
            RobotModelPreviewWindowContentView()
        }
        .defaultSize(width: 980, height: 680)
    }
}
