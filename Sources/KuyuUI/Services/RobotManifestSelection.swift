import Foundation
import KuyuScenarios

struct RobotManifestSelection {
    struct Resolution: Equatable {
        let path: String
        let didSwitch: Bool
        let reason: String?
    }

    static func desiredRobotManifestPath(for task: SimulationTaskMode) -> String {
        switch task {
        case .singleLift:
            return KuyuUIModelPaths.defaultSinglePropRobotManifestPath()
        case .attitude, .lift:
            return KuyuUIModelPaths.defaultRobotManifestPath()
        }
    }

    static func resolveForTask(
        configuredPath: String,
        taskMode: SimulationTaskMode
    ) -> Resolution {
        let trimmed = configuredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let desired = desiredRobotManifestPath(for: taskMode)
        if trimmed.isEmpty {
            return Resolution(path: desired, didSwitch: true, reason: "emptyPath")
        }
        if isRoArmM1RobotManifestPath(trimmed) {
            return Resolution(path: trimmed, didSwitch: false, reason: nil)
        }
        if taskMode == .singleLift, isQuadRobotManifestPath(trimmed) {
            return Resolution(path: desired, didSwitch: true, reason: "singleLiftUsesQuad")
        }
        if taskMode != .singleLift, isSinglePropRobotManifestPath(trimmed) {
            return Resolution(path: desired, didSwitch: true, reason: "quadUsesSingleProp")
        }
        return Resolution(path: trimmed, didSwitch: false, reason: nil)
    }

    static func isQuadRobotManifestPath(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower.contains("quad") || lower.contains("quadref")
    }

    static func isSinglePropRobotManifestPath(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower.contains("singleprop") || lower.contains("single-prop") || lower.contains("slift")
    }

    static func isRoArmM1RobotManifestPath(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower.contains("roarm-m1") || lower.contains("roarmm1")
    }
}
