import Foundation
import KuyuScenarios

struct DescriptorSelection {
    struct Resolution: Equatable {
        let path: String
        let didSwitch: Bool
        let reason: String?
    }

    static func desiredDescriptorPath(for task: SimulationTaskMode) -> String {
        switch task {
        case .singleLift:
            return KuyuUIModelPaths.defaultSinglePropDescriptorPath()
        case .attitude, .lift:
            return KuyuUIModelPaths.defaultDescriptorPath()
        }
    }

    static func resolveForTask(
        configuredPath: String,
        taskMode: SimulationTaskMode
    ) -> Resolution {
        let trimmed = configuredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let desired = desiredDescriptorPath(for: taskMode)
        if trimmed.isEmpty {
            return Resolution(path: desired, didSwitch: true, reason: "emptyPath")
        }
        if taskMode == .singleLift, isQuadDescriptorPath(trimmed) {
            return Resolution(path: desired, didSwitch: true, reason: "singleLiftUsesQuad")
        }
        if taskMode != .singleLift, isSinglePropDescriptorPath(trimmed) {
            return Resolution(path: desired, didSwitch: true, reason: "quadUsesSingleProp")
        }
        return Resolution(path: trimmed, didSwitch: false, reason: nil)
    }

    static func isQuadDescriptorPath(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower.contains("quad") || lower.contains("quadref")
    }

    static func isSinglePropDescriptorPath(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower.contains("singleprop") || lower.contains("single-prop") || lower.contains("slift")
    }
}
