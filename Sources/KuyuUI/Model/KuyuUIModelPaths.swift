import Foundation
import KuyuProfiles

public enum KuyuUIModelPaths {
    public static func defaultDescriptorPath() -> String {
        if let bundled = bundledDescriptorPath() {
            return bundled
        }
        if let source = sourceRootDescriptorPath() {
            return source
        }
        if let local = localDescriptorPath() {
            return local
        }
        return "Models/QuadRef/quadref.model.json"
    }

    public static func defaultSinglePropDescriptorPath() -> String {
        if let bundled = bundledSinglePropDescriptorPath() {
            return bundled
        }
        if let source = sourceRootSinglePropDescriptorPath() {
            return source
        }
        if let local = localSinglePropDescriptorPath() {
            return local
        }
        return "Models/SingleProp/singleprop.model.json"
    }

    public static func resolveDescriptorPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return defaultDescriptorPath()
        }
        if trimmed == "Models/QuadRef/quadref.model.json" {
            if let bundled = bundledDescriptorPath() {
                return bundled
            }
            if let source = sourceRootDescriptorPath() {
                return source
            }
            if let local = localDescriptorPath() {
                return local
            }
        }
        if trimmed == "Models/SingleProp/singleprop.model.json" {
            if let bundled = bundledSinglePropDescriptorPath() {
                return bundled
            }
            if let source = sourceRootSinglePropDescriptorPath() {
                return source
            }
            if let local = localSinglePropDescriptorPath() {
                return local
            }
        }
        if FileManager.default.fileExists(atPath: trimmed) {
            return trimmed
        }
        if let bundled = bundledDescriptorPath() {
            return bundled
        }
        if let source = sourceRootDescriptorPath() {
            return source
        }
        if let local = localDescriptorPath() {
            return local
        }
        return trimmed
    }

    public static func bundledDescriptorPath() -> String? {
        let subdirectories: [String?] = [
            "Models/QuadRef",
            "Resources/Models/QuadRef",
            nil
        ]
        for bundle in [Bundle.module, Bundle.main] {
            for subdir in subdirectories {
                if let url = bundle.url(
                    forResource: "quadref.model",
                    withExtension: "json",
                    subdirectory: subdir
                ) {
                    return url.path
                }
            }
        }
        return nil
    }

    public static func bundledSinglePropDescriptorPath() -> String? {
        let subdirectories: [String?] = [
            "Models/SingleProp",
            "Resources/Models/SingleProp",
            nil
        ]
        for bundle in [Bundle.module, Bundle.main] {
            for subdir in subdirectories {
                if let url = bundle.url(
                    forResource: "singleprop.model",
                    withExtension: "json",
                    subdirectory: subdir
                ) {
                    return url.path
                }
            }
        }
        return nil
    }

    public static func localDescriptorPath() -> String? {
        let candidates = [
            "Models/QuadRef/quadref.model.json",
            "../Models/QuadRef/quadref.model.json",
            "../../Models/QuadRef/quadref.model.json"
        ]

        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    public static func localSinglePropDescriptorPath() -> String? {
        let candidates = [
            "Models/SingleProp/singleprop.model.json",
            "../Models/SingleProp/singleprop.model.json",
            "../../Models/SingleProp/singleprop.model.json"
        ]

        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    public static func sourceRootDescriptorPath() -> String? {
        let fileURL = URL(fileURLWithPath: #filePath)
        var base = fileURL.deletingLastPathComponent()
        for _ in 0..<4 {
            base = base.deletingLastPathComponent()
        }
        let candidate = base.appendingPathComponent("Models/QuadRef/quadref.model.json")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate.path
        }
        return nil
    }

    public static func sourceRootSinglePropDescriptorPath() -> String? {
        let fileURL = URL(fileURLWithPath: #filePath)
        var base = fileURL.deletingLastPathComponent()
        for _ in 0..<4 {
            base = base.deletingLastPathComponent()
        }
        let candidate = base.appendingPathComponent("Models/SingleProp/singleprop.model.json")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate.path
        }
        return nil
    }
}
