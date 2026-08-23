import KuyuMojoTrainingRuntime
import KuyuTrainingApplication
import KuyuUI
import SwiftUI

@main
struct TrainingInspectionApp: App {
  private let runner = LearningUpdateCoordinator(
    executor: KuyuMojoLearningUpdateExecutor()
  )

  var body: some Scene {
    WindowGroup {
      KuyuWorkspaceView(runner: runner)
    }
  }
}
