import Foundation
import KuyuTraining

public struct ManasMLXTrainingWorkerProcessConfigurationFactory: Sendable {
    public enum FactoryError: Error, Sendable, Equatable {
        case missingRuntimeResourceBundle(name: String, searchedPaths: [String])
        case missingMetalLibrary(bundlePath: String)
    }

    public static let mlxResourceBundleName = "mlx-swift_Cmlx.bundle"

    public init() {}

    public func configuration(
        executableURL: URL,
        launchRootDirectory: URL
    ) throws -> TrainingRunWorkerProcessConfiguration {
        TrainingRunWorkerProcessConfiguration(
            executableURL: executableURL,
            launchRootDirectory: launchRootDirectory,
            resourceBundles: [try mlxResourceBundle(for: executableURL)]
        )
    }

    public func userCache(
        executableURL: URL,
        pathComponents: [String] = ["Kuyu", "TrainingWorkerLaunches"],
        fileManager: FileManager = .default
    ) throws -> TrainingRunWorkerProcessConfiguration {
        try TrainingRunWorkerProcessConfiguration.userCache(
            executableURL: executableURL,
            resourceBundles: [mlxResourceBundle(for: executableURL)],
            pathComponents: pathComponents,
            fileManager: fileManager
        )
    }

    private func mlxResourceBundle(
        for executableURL: URL
    ) throws -> TrainingRunWorkerResourceBundle {
        let candidates = resourceBundleCandidates(for: executableURL)
        guard let bundleURL = candidates.first(where: Self.isDirectory) else {
            throw FactoryError.missingRuntimeResourceBundle(
                name: Self.mlxResourceBundleName,
                searchedPaths: candidates.map(\.path)
            )
        }
        let metalLibraryCandidates = [
            bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent("default.metallib", isDirectory: false),
            bundleURL.appendingPathComponent("default.metallib", isDirectory: false),
        ]
        guard metalLibraryCandidates.contains(where: Self.isRegularFile) else {
            throw FactoryError.missingMetalLibrary(bundlePath: bundleURL.path)
        }
        return TrainingRunWorkerResourceBundle(sourceURL: bundleURL)
    }

    private func resourceBundleCandidates(for executableURL: URL) -> [URL] {
        let executable = executableURL.standardizedFileURL
        let executableDirectory = executable.deletingLastPathComponent()
        var roots = [executableDirectory]
        let contentsDirectory = executableDirectory.deletingLastPathComponent()
        let applicationBundle = contentsDirectory.deletingLastPathComponent()
        if executableDirectory.lastPathComponent == "MacOS",
           contentsDirectory.lastPathComponent == "Contents",
           applicationBundle.pathExtension == "app" {
            roots.insert(
                contentsDirectory.appendingPathComponent("Resources", isDirectory: true),
                at: 0
            )
            roots.append(applicationBundle)
        }
        var paths = Set<String>()
        return roots.compactMap { root in
            let candidate = root.appendingPathComponent(
                Self.mlxResourceBundleName,
                isDirectory: true
            )
            return paths.insert(candidate.path).inserted ? candidate : nil
        }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
    }
}
