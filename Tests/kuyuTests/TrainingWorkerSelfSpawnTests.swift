import Darwin
import Foundation
import KuyuTraining
import KuyuWorkerRuntime
import Testing

@Suite("Training worker self-spawn", .serialized)
struct TrainingWorkerSelfSpawnTests {
    @Test(.timeLimit(.minutes(1)))
    func productionExecutableRunsTheDigestBoundWorkerService() async throws {
        let executableURL = try productionKuyuExecutableURL()
        let root = try temporaryDirectory("kuyu-worker-self-spawn")
        let launchRoot = root.appendingPathComponent("launches", isDirectory: true)
        let artifactParent = root.appendingPathComponent("artifacts", isDirectory: true)
        let artifactRoot = artifactParent.appendingPathComponent("run", isDirectory: true)
        let sourceParent = root.appendingPathComponent("sources", isDirectory: true)
        let sourceRoot = sourceParent.appendingPathComponent("invalid-model", isDirectory: true)
        try FileManager.default.createDirectory(at: artifactParent, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try Data("invalid-model-fixture".utf8).write(
            to: sourceRoot.appendingPathComponent("model.json", isDirectory: false)
        )
        let source = try TrainingRunWorkerSourceIntegrityVerifier(
            allowedSourceRoots: [sourceParent]
        ).pinnedReference(
            ModelBundleReference(
                bundleID: "self-spawn-invalid-source",
                kind: .source,
                url: sourceRoot
            )
        )
        let runID = TrainingRunID("worker-self-spawn")
        let launch = TrainingRunWorkerLaunchArtifact(
            operation: .start(
                TrainingRunRequest(
                    runID: runID,
                    artifactRoot: artifactRoot,
                    taskProfileID: "lift",
                    policyContract: ReferenceQuadrotorLearningContracts
                        .temporalCTBRPolicyContract(),
                    actionContract: ReferenceQuadrotorLearningContracts
                        .bodyRateActionContract(),
                    sourceBundle: source
                )
            )
        )
        let configuration = try ManasMLXTrainingWorkerProcessConfigurationFactory().configuration(
            executableURL: executableURL,
            launchRootDirectory: launchRoot
        )
        let handle = try await TrainingRunWorkerProcessLauncher(
            configuration: configuration
        ).launch(launch)

        let summary = try await handle.wait()

        #expect(summary.terminalState == .failed)
        #expect(!summary.failureReasons.isEmpty)
        let errorOutput = try String(contentsOf: handle.standardErrorURL, encoding: .utf8)
        #expect(!errorOutput.isEmpty)

        let outcome = try TrainingRunSummaryOutcomeArtifactStore().validatedArtifact(
            in: artifactRoot,
            expectedRunID: runID,
            expectedWorkerAttemptIdentity: handle.workerAttemptIdentity
        )
        #expect(outcome.summary.terminalState == .failed)
        #expect(outcome.summary == summary)
        let launchDirectory = TrainingRunWorkerLaunchArtifactStore(
            rootDirectory: launchRoot
        ).launchDirectory(for: launch.launchID)
        #expect(FileManager.default.fileExists(
            atPath: launchDirectory
                .appendingPathComponent(
                    TrainingRunWorkerSourceSnapshotStore.snapshotDirectoryName,
                    isDirectory: true
                ).path
        ))
        #expect(FileManager.default.fileExists(
            atPath: launchDirectory
                .appendingPathComponent(
                    TrainingRunWorkerExecutableStager.stagingDirectoryName,
                    isDirectory: true
                )
                .appendingPathComponent(
                    ManasMLXTrainingWorkerProcessConfigurationFactory.mlxResourceBundleName,
                    isDirectory: true
                ).path
        ))
        #expect(FileManager.default.fileExists(
            atPath: launchDirectory
                .appendingPathComponent(
                    TrainingRunWorkerProgressArtifact.directoryName,
                    isDirectory: true
                ).path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: artifactRoot
                .appendingPathComponent(
                    TrainingRunWorkerProgressArtifact.directoryName,
                    isDirectory: true
                ).path
        ))
        let registration = try TrainingRunWorkerRegistrationStore(
            ownershipRootDirectory: launchRoot.appendingPathComponent(
                TrainingRunWorkerLease.ownershipDirectoryName,
                isDirectory: true
            )
        ).registration(for: artifactRoot)
        #expect(registration == nil)
    }

    private func productionKuyuExecutableURL() throws -> URL {
        let environmentRoot = ProcessInfo.processInfo.environment["BUILT_PRODUCTS_DIR"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        let candidates = ([environmentRoot].compactMap { $0 } + loadedTestProductDirectories()).map {
            $0.appendingPathComponent("kuyu", isDirectory: false)
        }
        return try #require(candidates.first(where: { candidate in
            FileManager.default.isExecutableFile(atPath: candidate.path)
        }))
    }

    private func loadedTestProductDirectories() -> [URL] {
        var directories: [URL] = []
        for index in 0..<_dyld_image_count() {
            guard let imageName = _dyld_get_image_name(index) else { continue }
            var candidate = URL(fileURLWithPath: String(cString: imageName), isDirectory: false)
            while candidate.path != "/", candidate.pathExtension != "xctest" {
                candidate.deleteLastPathComponent()
            }
            guard candidate.pathExtension == "xctest" else { continue }
            directories.append(candidate.deletingLastPathComponent())
        }
        return directories
    }

    private func temporaryDirectory(_ label: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "\(label)-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }
}
