import Foundation
import KuyuPhysics
import KuyuScenarios

public enum KuyuUIModelPaths {
    public static func defaultKuyuExecutablePath() -> String {
        if let bundled = Bundle.main.executableURL,
           bundled.lastPathComponent == "kuyu",
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled.path
        }
        if let source = sourceRootKuyuExecutablePath() {
            return source
        }
        return ""
    }

    public static func defaultRobotManifestPath() -> String {
        if let bundled = bundledRobotManifestPath() {
            return bundled
        }
        if let source = sourceRootRobotManifestPath() {
            return source
        }
        if let local = localRobotManifestPath() {
            return local
        }
        return "Models/QuadRef/quadref.kuyurobot.json"
    }

    public static func defaultSinglePropRobotManifestPath() -> String {
        if let bundled = bundledSinglePropRobotManifestPath() {
            return bundled
        }
        if let source = sourceRootSinglePropRobotManifestPath() {
            return source
        }
        if let local = localSinglePropRobotManifestPath() {
            return local
        }
        return "Models/SingleProp/singleprop.kuyurobot.json"
    }

    public static func defaultRoArmM1RobotManifestPath() -> String {
        if let bundled = bundledRoArmM1RobotManifestPath() {
            return bundled
        }
        if let source = sourceRootRoArmM1RobotManifestPath() {
            return source
        }
        if let local = localRoArmM1RobotManifestPath() {
            return local
        }
        return "Models/RoArmM1/roarm-m1.kuyurobot.json"
    }

    public static func resolveRobotManifestPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return defaultRobotManifestPath()
        }
        if trimmed == "Models/QuadRef/quadref.kuyurobot.json" {
            if let bundled = bundledRobotManifestPath() {
                return bundled
            }
            if let source = sourceRootRobotManifestPath() {
                return source
            }
            if let local = localRobotManifestPath() {
                return local
            }
        }
        if trimmed == "Models/SingleProp/singleprop.kuyurobot.json" {
            if let bundled = bundledSinglePropRobotManifestPath() {
                return bundled
            }
            if let source = sourceRootSinglePropRobotManifestPath() {
                return source
            }
            if let local = localSinglePropRobotManifestPath() {
                return local
            }
        }
        if trimmed == "Models/RoArmM1/roarm-m1.kuyurobot.json" {
            if let bundled = bundledRoArmM1RobotManifestPath() {
                return bundled
            }
            if let source = sourceRootRoArmM1RobotManifestPath() {
                return source
            }
            if let local = localRoArmM1RobotManifestPath() {
                return local
            }
        }
        return trimmed
    }

    public static func bundledRobotManifestPath() -> String? {
        let subdirectories: [String?] = [
            "Models/QuadRef",
            "Resources/Models/QuadRef",
            nil
        ]
        for bundle in [Bundle.module, Bundle.main] {
            for subdir in subdirectories {
                if let url = bundle.url(
                    forResource: "quadref.kuyurobot",
                    withExtension: "json",
                    subdirectory: subdir
                ) {
                    return url.path
                }
            }
        }
        return nil
    }

    public static func bundledSinglePropRobotManifestPath() -> String? {
        let subdirectories: [String?] = [
            "Models/SingleProp",
            "Resources/Models/SingleProp",
            nil
        ]
        for bundle in [Bundle.module, Bundle.main] {
            for subdir in subdirectories {
                if let url = bundle.url(
                    forResource: "singleprop.kuyurobot",
                    withExtension: "json",
                    subdirectory: subdir
                ) {
                    return url.path
                }
            }
        }
        return nil
    }

    public static func bundledRoArmM1RobotManifestPath() -> String? {
        let subdirectories: [String?] = [
            "Models/RoArmM1",
            "Resources/Models/RoArmM1",
            nil
        ]
        for bundle in [Bundle.module, Bundle.main] {
            for subdir in subdirectories {
                if let url = bundle.url(
                    forResource: "roarm-m1.kuyurobot",
                    withExtension: "json",
                    subdirectory: subdir
                ) {
                    return url.path
                }
            }
        }
        return nil
    }

    public static func localRobotManifestPath() -> String? {
        let candidates = [
            "Models/QuadRef/quadref.kuyurobot.json",
            "../Models/QuadRef/quadref.kuyurobot.json",
            "../../Models/QuadRef/quadref.kuyurobot.json"
        ]

        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    public static func localSinglePropRobotManifestPath() -> String? {
        let candidates = [
            "Models/SingleProp/singleprop.kuyurobot.json",
            "../Models/SingleProp/singleprop.kuyurobot.json",
            "../../Models/SingleProp/singleprop.kuyurobot.json"
        ]

        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    public static func localRoArmM1RobotManifestPath() -> String? {
        let candidates = [
            "Models/RoArmM1/roarm-m1.kuyurobot.json",
            "../Models/RoArmM1/roarm-m1.kuyurobot.json",
            "../../Models/RoArmM1/roarm-m1.kuyurobot.json"
        ]

        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    public static func sourceRootRobotManifestPath() -> String? {
        let fileURL = URL(fileURLWithPath: #filePath)
        var base = fileURL.deletingLastPathComponent()
        for _ in 0..<3 {
            base = base.deletingLastPathComponent()
        }
        let candidate = base.appendingPathComponent("Sources/KuyuUI/Resources/Models/QuadRef/quadref.kuyurobot.json")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate.path
        }
        return nil
    }

    public static func sourceRootSinglePropRobotManifestPath() -> String? {
        let fileURL = URL(fileURLWithPath: #filePath)
        var base = fileURL.deletingLastPathComponent()
        for _ in 0..<3 {
            base = base.deletingLastPathComponent()
        }
        let candidate = base.appendingPathComponent("Sources/KuyuUI/Resources/Models/SingleProp/singleprop.kuyurobot.json")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate.path
        }
        return nil
    }

    public static func sourceRootRoArmM1RobotManifestPath() -> String? {
        let fileURL = URL(fileURLWithPath: #filePath)
        var base = fileURL.deletingLastPathComponent()
        for _ in 0..<3 {
            base = base.deletingLastPathComponent()
        }
        let candidate = base.appendingPathComponent("Sources/KuyuUI/Resources/Models/RoArmM1/roarm-m1.kuyurobot.json")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate.path
        }
        return nil
    }

    public static func sourceRootKuyuExecutablePath() -> String? {
        let fileURL = URL(fileURLWithPath: #filePath)
        var base = fileURL.deletingLastPathComponent()
        for _ in 0..<3 {
            base = base.deletingLastPathComponent()
        }
        let candidates = [
            base.appendingPathComponent(".build/debug/kuyu"),
            base.appendingPathComponent(".build/arm64-apple-macosx/debug/kuyu"),
            base.appendingPathComponent(".build/release/kuyu"),
            base.appendingPathComponent(".build/arm64-apple-macosx/release/kuyu")
        ]
        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            return candidate.path
        }
        return nil
    }
}
