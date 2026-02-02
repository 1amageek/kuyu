import Foundation

enum KuyuUIModelPaths {
    static func defaultDescriptorPath() -> String {
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

    static func resolveDescriptorPath(_ path: String) -> String {
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

    static func bundledDescriptorPath() -> String? {
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

    static func localDescriptorPath() -> String? {
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

    static func sourceRootDescriptorPath() -> String? {
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
}
