import Foundation
import ManasCore

public enum ManasMLXCheckpointCompatibilityFailure: Sendable, Equatable, CustomStringConvertible {
    case incompatibleDriveCount(expected: Int, actual: Int)
    case missingReflexConfig
    case missingReflexCheckpoint(URL)
    case invalidModelBundle(String)

    public var description: String {
        switch self {
        case .incompatibleDriveCount(let expected, let actual):
            return "incompatible-checkpoint-drive-count(expected: \(expected), actual: \(actual))"
        case .missingReflexConfig:
            return "missing-reflex-config"
        case .missingReflexCheckpoint:
            return "missing-reflex-checkpoint"
        case .invalidModelBundle(let reason):
            return "invalid-model-bundle(\(reason))"
        }
    }
}

public struct ManasMLXCheckpointCompatibility: Sendable {
    public let expectedDriveCount: Int

    public init(expectedDriveCount: Int) {
        self.expectedDriveCount = expectedDriveCount
    }

    public func validate(snapshotURL: URL) throws -> ManasMLXCheckpointCompatibilityFailure? {
        let manifestURL = snapshotURL.appendingPathComponent("model.json")
        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(ManasMLXModelManifest.self, from: data)

        guard manifest.coreConfig.driveCount == expectedDriveCount else {
            return .incompatibleDriveCount(
                expected: expectedDriveCount,
                actual: manifest.coreConfig.driveCount
            )
        }
        guard manifest.reflexConfig != nil else {
            return .missingReflexConfig
        }
        let reflexURL = snapshotURL.appendingPathComponent("reflex.safetensors")
        guard FileManager.default.fileExists(atPath: reflexURL.path) else {
            return .missingReflexCheckpoint(reflexURL)
        }
        do {
            _ = try ManasModelBundleValidator().loadAndValidate(from: snapshotURL)
        } catch {
            return .invalidModelBundle("\(error)")
        }
        return nil
    }
}
