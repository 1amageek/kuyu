import Foundation
import KuyuPhysics

public struct ManasMLXE2EPreflightReport: Sendable, Codable, Equatable {
    public let descriptorPath: String?
    public let descriptorLoaded: Bool
    public let sourceCheckpointURL: URL?
    public let sourceCheckpointLoadable: Bool
    public let mlxRuntimeReady: Bool

    public init(
        descriptorPath: String?,
        descriptorLoaded: Bool,
        sourceCheckpointURL: URL?,
        sourceCheckpointLoadable: Bool,
        mlxRuntimeReady: Bool
    ) {
        self.descriptorPath = descriptorPath
        self.descriptorLoaded = descriptorLoaded
        self.sourceCheckpointURL = sourceCheckpointURL
        self.sourceCheckpointLoadable = sourceCheckpointLoadable
        self.mlxRuntimeReady = mlxRuntimeReady
    }
}

public enum ManasMLXE2EPreflightError: Error, Sendable, Equatable, CustomStringConvertible {
    case descriptorLoadFailed(String)
    case missingCheckpointFile(String)
    case checkpointLoadFailed(String)
    case mlxRuntimeUnavailable(String)

    public var description: String {
        switch self {
        case .descriptorLoadFailed(let reason):
            return "descriptor-load-failed: \(reason)"
        case .missingCheckpointFile(let path):
            return "missing-checkpoint-file: \(path)"
        case .checkpointLoadFailed(let reason):
            return "checkpoint-load-failed: \(reason)"
        case .mlxRuntimeUnavailable(let reason):
            return "mlx-runtime-unavailable: \(reason)"
        }
    }
}

@MainActor
public struct ManasMLXE2EPreflight {
    private let runtimePreflight: MLXRuntimePreflight

    public init(runtimePreflight: MLXRuntimePreflight = MLXRuntimePreflight()) {
        self.runtimePreflight = runtimePreflight
    }

    public func check(
        descriptorPath: String,
        sourceCheckpointURL: URL? = nil,
        requireSourceCheckpoint: Bool = false,
        metallibURL: URL? = nil,
        executablePath: String? = nil,
        fileManager: FileManager = .default
    ) throws -> ManasMLXE2EPreflightReport {
        do {
            try runtimePreflight.check(
                metallibURL: metallibURL,
                executablePath: executablePath,
                fileManager: fileManager
            )
        } catch {
            throw ManasMLXE2EPreflightError.mlxRuntimeUnavailable("\(error)")
        }

        let trimmedDescriptor = descriptorPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let descriptorLoaded: Bool
        if trimmedDescriptor.isEmpty {
            descriptorLoaded = false
        } else {
            do {
                _ = try RobotDescriptorLoader().loadDescriptor(path: trimmedDescriptor)
                descriptorLoaded = true
            } catch {
                throw ManasMLXE2EPreflightError.descriptorLoadFailed("\(error)")
            }
        }

        var sourceCheckpointLoadable = false
        if let sourceCheckpointURL {
            try validateCheckpointFiles(at: sourceCheckpointURL, fileManager: fileManager)
            do {
                _ = try ManasMLXModelStore().loadModel(from: sourceCheckpointURL)
                sourceCheckpointLoadable = true
            } catch {
                throw ManasMLXE2EPreflightError.checkpointLoadFailed("\(error)")
            }
        } else if requireSourceCheckpoint {
            throw ManasMLXE2EPreflightError.missingCheckpointFile("source checkpoint URL")
        }

        return ManasMLXE2EPreflightReport(
            descriptorPath: trimmedDescriptor.isEmpty ? nil : trimmedDescriptor,
            descriptorLoaded: descriptorLoaded,
            sourceCheckpointURL: sourceCheckpointURL,
            sourceCheckpointLoadable: sourceCheckpointLoadable,
            mlxRuntimeReady: true
        )
    }

    private func validateCheckpointFiles(at directory: URL, fileManager: FileManager) throws {
        for fileName in ["model.json", "core.safetensors"] {
            let url = directory.appendingPathComponent(fileName)
            guard fileManager.fileExists(atPath: url.path) else {
                throw ManasMLXE2EPreflightError.missingCheckpointFile(url.path)
            }
        }
    }
}
