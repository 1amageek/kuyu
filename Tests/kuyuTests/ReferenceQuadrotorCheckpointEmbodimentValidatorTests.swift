import Foundation
import KuyuPhysics
import KuyuTraining
import KuyuUI
import Testing
@testable import KuyuMLX

@Test(.timeLimit(.minutes(1)))
func checkpointEmbodimentValidatorAcceptsTheBoundRobotAndRejectsAnotherRobot() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "kuyu-checkpoint-embodiment-binding-\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer {
        do {
            try FileManager.default.removeItem(at: root)
        } catch {
            Issue.record("Failed to remove checkpoint embodiment binding fixture: \(error)")
        }
    }

    let robotManifestPath = KuyuUIModelPaths.defaultRobotManifestPath()
    let loadedRobot = try KuyuModelLoader().loadRobot(path: robotManifestPath)
    let checkpointURL = root.appendingPathComponent("source.manasbundle", isDirectory: true)
    let starterContract = try ReferenceQuadrotorStarterCheckpointContractService().contract(
        taskMode: .attitude
    )
    _ = try ManasMLXTemporalCheckpointWriter().write(
        request: ManasMLXTemporalCheckpointWriteRequest(
            checkpointURL: checkpointURL,
            name: "bound-reference-source",
            policyContract: ReferenceQuadrotorLearningContracts.temporalCTBRPolicyContract(
                observationDimension: starterContract.expectedObservationChannelCount,
                historyLength: starterContract.historyLength
            ),
            observationContract: starterContract.observationContract,
            actionContract: ReferenceQuadrotorLearningContracts.bodyRateActionContract(),
            embodiment: loadedRobot.embodiment,
            hiddenSize: 8,
            initializationSeed: starterContract.initializationSeed,
            starterActionMean: starterContract.starterActionMean
        )
    )

    let validator = ReferenceQuadrotorCheckpointEmbodimentValidator()
    let identity = try validator.validatedRobotIdentity(
        checkpointURL: checkpointURL,
        robotManifestPath: robotManifestPath
    )
    #expect(identity.robotID == loadedRobot.manifest.robotID)

    let otherRobotManifestPath = KuyuUIModelPaths.defaultSinglePropRobotManifestPath()
    do {
        _ = try validator.validatedRobotIdentity(
            checkpointURL: checkpointURL,
            robotManifestPath: otherRobotManifestPath
        )
        Issue.record("A checkpoint bound to QuadRef was accepted for SingleProp.")
    } catch let error as ReferenceQuadrotorCheckpointEmbodimentValidator.ValidationError {
        guard case .embodimentHashMismatch = error else {
            Issue.record("Unexpected checkpoint embodiment validation error: \(error)")
            return
        }
    } catch {
        Issue.record("Unexpected checkpoint embodiment validation error type: \(error)")
    }
}

@Test func checkpointEmbodimentValidatorRequiresRobotManifestPath() {
    #expect(throws: ReferenceQuadrotorCheckpointEmbodimentValidator.ValidationError
        .robotManifestPathRequired) {
        _ = try ReferenceQuadrotorCheckpointEmbodimentValidator().validatedRobotIdentity(
            checkpointURL: URL(fileURLWithPath: "/tmp/missing.manasbundle", isDirectory: true),
            robotManifestPath: ""
        )
    }
}
