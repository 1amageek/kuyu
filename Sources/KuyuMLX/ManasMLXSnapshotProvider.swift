import Foundation
import KuyuTraining
import ManasCore

public struct ManasMLXSnapshotProvider: SnapshotProviding {
    public enum SnapshotError: Error, Sendable, Equatable, CustomStringConvertible {
        case sourceCheckpointMissing(URL)
        case sourceCheckpointNotDirectory(URL)
        case missingRequiredFile(URL)
        case destinationConflict(URL)

        public var description: String {
            switch self {
            case .sourceCheckpointMissing(let url):
                return "source-checkpoint-missing: \(url.path)"
            case .sourceCheckpointNotDirectory(let url):
                return "source-checkpoint-not-directory: \(url.path)"
            case .missingRequiredFile(let url):
                return "missing-required-file: \(url.path)"
            case .destinationConflict(let url):
                return "destination-conflict: \(url.path)"
            }
        }
    }

    public let sourceCheckpointURL: URL
    public let workerRootURL: URL
    public let policyID: String
    public let descriptorID: String?
    public let configHash: String?
    public let requiredFiles: [String]

    public init(
        sourceCheckpointURL: URL,
        workerRootURL: URL,
        policyID: String = "manasMLX",
        descriptorID: String? = nil,
        configHash: String? = nil,
        requiredFiles: [String] = [
            "model.json",
            "core.safetensors",
            "reflex.safetensors",
            ManasModelBundleManifest.defaultFileName
        ]
    ) {
        self.sourceCheckpointURL = sourceCheckpointURL
        self.workerRootURL = workerRootURL
        self.policyID = policyID
        self.descriptorID = descriptorID
        self.configHash = configHash
        self.requiredFiles = requiredFiles
    }

    public func leaseSnapshot(workerIndex: Int) async throws -> SnapshotLease {
        let source = sourceCheckpointURL.standardizedFileURL
        let destination = workerRootURL
            .appendingPathComponent("worker-\(workerIndex)", isDirectory: true)
            .appendingPathComponent("snapshot", isDirectory: true)
            .standardizedFileURL

        try validateSourceCheckpoint(at: source)
        try prepareDestination(destination)
        try FileManager.default.copyItem(at: source, to: destination)

        let identity = SnapshotIdentity(
            policyID: policyID,
            snapshotID: "\(policyID)-worker-\(workerIndex)-\(UUID().uuidString)",
            descriptorID: descriptorID,
            configHash: configHash
        )
        return SnapshotLease(
            snapshot: WorkerSnapshot(
                identity: identity,
                workerIndex: workerIndex,
                checkpointURL: destination
            )
        )
    }

    private func validateSourceCheckpoint(at source: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory) else {
            throw SnapshotError.sourceCheckpointMissing(source)
        }
        guard isDirectory.boolValue else {
            throw SnapshotError.sourceCheckpointNotDirectory(source)
        }

        for fileName in requiredFiles {
            let fileURL = source.appendingPathComponent(fileName, isDirectory: false)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw SnapshotError.missingRequiredFile(fileURL)
            }
        }
        _ = try ManasModelBundleValidator().loadAndValidate(from: source)
    }

    private func prepareDestination(_ destination: URL) throws {
        let workerDirectory = destination.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            throw SnapshotError.destinationConflict(destination)
        }
        try FileManager.default.createDirectory(at: workerDirectory, withIntermediateDirectories: true)
    }
}
