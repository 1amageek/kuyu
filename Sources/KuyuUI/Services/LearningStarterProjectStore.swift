import Foundation
import KuyuMLX
import KuyuTraining

public enum LearningStarterProjectStoreError: Error, Equatable, LocalizedError, Sendable {
    case checkpointWriterDidNotCreateRequiredFiles([String])

    public var errorDescription: String? {
        switch self {
        case .checkpointWriterDidNotCreateRequiredFiles(let files):
            return "Starter checkpoint is incomplete: \(files.joined(separator: ", "))"
        }
    }
}

public struct LearningStarterProjectStore: Sendable {
    public let projectRoot: URL
    private let now: @Sendable () -> Date
    private let checkpointRequirements: ManasMLXStarterCheckpointFileRequirements

    public init(
        projectRoot: URL? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        checkpointRequirements: ManasMLXStarterCheckpointFileRequirements? = nil
    ) {
        self.projectRoot = projectRoot ?? Self.defaultProjectRoot()
        self.now = now
        self.checkpointRequirements = checkpointRequirements ?? ManasMLXStarterCheckpointFileRequirements()
    }

    @MainActor
    public func prepareStarterProject(
        regenerateSourceCheckpoint: Bool = false,
        policyContract: LearningProjectPolicyContract,
        checkpointWriter: @MainActor (URL) async throws -> Void
    ) async throws -> LearningStarterProject {
        let fileManager = FileManager.default
        let sourceCheckpoint = projectRoot
            .appendingPathComponent("SourceCheckpoint.manasbundle", isDirectory: true)
        let runsRoot = projectRoot
            .appendingPathComponent("Runs", isDirectory: true)

        try fileManager.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: runsRoot, withIntermediateDirectories: true)

        if regenerateSourceCheckpoint || !checkpointIsComplete(at: sourceCheckpoint, policyContract: policyContract) {
            try await TransactionalDirectoryPublisher().publish(to: sourceCheckpoint) { stagingURL in
                try await checkpointWriter(stagingURL)
                let missing = missingCheckpointFiles(at: stagingURL, policyContract: policyContract)
                guard missing.isEmpty else {
                    throw LearningStarterProjectStoreError.checkpointWriterDidNotCreateRequiredFiles(missing)
                }
            }
        }

        let artifactRoot = try makeNextRunArtifactRoot()

        return LearningStarterProject(
            projectRoot: projectRoot,
            sourceCheckpoint: sourceCheckpoint,
            artifactRoot: artifactRoot
        )
    }

    public func makeNextRunArtifactRoot() throws -> URL {
        let runsRoot = projectRoot
            .appendingPathComponent("Runs", isDirectory: true)
        try FileManager.default.createDirectory(at: runsRoot, withIntermediateDirectories: true)

        let stamp = max(0, Int(now().timeIntervalSince1970))
        var candidate = runsRoot.appendingPathComponent("run-\(stamp)", isDirectory: true)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = runsRoot.appendingPathComponent("run-\(stamp)-\(suffix)", isDirectory: true)
            suffix += 1
        }
        return candidate
    }

    public func artifactRootIsReusable(_ url: URL) throws -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return true
        }
        guard isDirectory.boolValue else {
            return false
        }
        let contents = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: []
        )
        return contents.isEmpty
    }

    public func checkpointIsComplete(at url: URL) -> Bool {
        checkpointIsComplete(
            at: url,
            policyContract: .simpleFeedForward(
                observationDimension: 1,
                actionDimension: 1,
                actionEncoding: .directMotor
            )
        )
    }

    public func checkpointIsComplete(
        at url: URL,
        policyContract: LearningProjectPolicyContract
    ) -> Bool {
        checkpointRequirements.isComplete(at: url, policyContract: policyContract)
    }

    private func missingCheckpointFiles(
        at url: URL,
        policyContract: LearningProjectPolicyContract
    ) -> [String] {
        checkpointRequirements.missingFiles(at: url, policyContract: policyContract)
    }

    private static func defaultProjectRoot() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support
            .appendingPathComponent("Bounded", isDirectory: true)
            .appendingPathComponent("StarterProject", isDirectory: true)
            .appendingPathComponent("DroneLift", isDirectory: true)
    }
}
