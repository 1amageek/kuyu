import ArgumentParser
import KuyuMLX
import KuyuTraining

enum LearningCampaignWorldExecution: String, CaseIterable, ExpressibleByArgument {
  case auto
  case accelerated
  case cpu

  func requirement(task: LearningCampaignTask) -> VectorizedWorldExecutionRequirement {
    switch self {
    case .auto:
      return task == .attitude
        ? .preferAcceleratorSharedWorld
        : .acceleratorSharedWorld
    case .accelerated:
      return .acceleratorSharedWorld
    case .cpu:
      return .isolatedCpuWorlds
    }
  }
}
