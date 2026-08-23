import KuyuTrainingApplication
import SwiftUI

public struct KuyuWorkspaceView: View {
  private enum Destination: String, CaseIterable, Identifiable {
    case training
    case robot

    var id: String { rawValue }

    var title: String {
      switch self {
      case .training:
        "Training"
      case .robot:
        "Robot Inspection"
      }
    }

    var symbol: String {
      switch self {
      case .training:
        "chart.line.uptrend.xyaxis"
      case .robot:
        "cube.transparent"
      }
    }
  }

  private let runner: any LearningUpdateRunning
  @State private var destination: Destination? = .training

  public init(runner: any LearningUpdateRunning) {
    self.runner = runner
  }

  public var body: some View {
    NavigationSplitView {
      List(Destination.allCases, selection: $destination) { destination in
        Label(destination.title, systemImage: destination.symbol)
          .tag(destination)
      }
      .navigationTitle("Kuyu")
      .navigationSplitViewColumnWidth(min: 180, ideal: 220)
    } detail: {
      switch destination ?? .training {
      case .training:
        LearningUpdateWorkspaceView(runner: runner)
      case .robot:
        RobotModelPreviewWindowContentView()
          .navigationTitle("Robot Inspection")
      }
    }
    .onChange(of: destination) { _, selected in
      KuyuUIEventLogger.record(
        action: "navigate",
        task: "workspace",
        identifier: (selected ?? .training).rawValue
      )
    }
  }
}
