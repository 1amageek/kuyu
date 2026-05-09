import Foundation
import KuyuCore
import KuyuScenarios
import KuyuTraining
import ManasCore
import ManasMLXModels
import MLX
import MLXNN

public struct ManasMLXRolloutPolicyFactory: ReferenceQuadrotorPolicyFactory {
    public enum FactoryError: Error, Equatable {
        case missingReflexConfig
        case missingCoreCheckpoint(URL)
        case missingReflexCheckpoint(URL)
    }

    public let policyID: String
    public let snapshotDirectory: URL
    public let useQualityGating: Bool
    public let descendingVector: [Double]?
    public let retainCoreState: Bool

    public init(
        snapshotDirectory: URL,
        policyID: String = "manasMLX",
        useQualityGating: Bool = true,
        descendingVector: [Double]? = nil,
        retainCoreState: Bool = true
    ) {
        self.snapshotDirectory = snapshotDirectory
        self.policyID = policyID
        self.useQualityGating = useQualityGating
        self.descendingVector = descendingVector
        self.retainCoreState = retainCoreState
    }

    public func makePolicy(
        definition: ReferenceQuadrotorScenarioDefinition,
        workerIndex: Int
    ) throws -> any ReferenceQuadrotorEnvironmentPolicy {
        _ = try ManasModelBundleValidator().loadAndValidate(from: snapshotDirectory)

        let manifestURL = snapshotDirectory.appendingPathComponent("model.json")
        let manifestData = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(ManasMLXModelManifest.self, from: manifestData)

        guard let reflexConfig = manifest.reflexConfig else {
            throw FactoryError.missingReflexConfig
        }

        let coreURL = snapshotDirectory.appendingPathComponent("core.safetensors")
        guard FileManager.default.fileExists(atPath: coreURL.path) else {
            throw FactoryError.missingCoreCheckpoint(coreURL)
        }
        let reflexURL = snapshotDirectory.appendingPathComponent("reflex.safetensors")
        guard FileManager.default.fileExists(atPath: reflexURL.path) else {
            throw FactoryError.missingReflexCheckpoint(reflexURL)
        }

        let core = ManasMLXCore(config: manifest.coreConfig)
        let coreArrays = try MLX.loadArrays(url: coreURL)
        core.update(parameters: ModuleParameters.unflattened(coreArrays))

        let reflex = ManasMLXReflex(config: reflexConfig)
        let reflexArrays = try MLX.loadArrays(url: reflexURL)
        reflex.update(parameters: ModuleParameters.unflattened(reflexArrays))

        let observationMode = ManasMLXObservationMode.checkpointMode(
            coreInputSize: manifest.coreConfig.inputSize
        )
        let cut = try ManasMLXCut(
            coreModel: core,
            reflexModel: reflex,
            useQualityGating: useQualityGating,
            observationMode: observationMode,
            descendingVector: descendingVector,
            retainCoreState: retainCoreState
        )
        return ManasMLXRolloutPolicy(policyID: policyID, cut: cut)
    }
}

public struct ManasMLXRolloutPolicy: ReferenceQuadrotorEnvironmentPolicy {
    public let policyID: String
    private var cut: ManasMLXCut

    public init(policyID: String, cut: ManasMLXCut) {
        self.policyID = policyID
        self.cut = cut
    }

    public mutating func action(for observation: EnvironmentObservation) async throws -> EnvironmentAction {
        let output = try cut.update(samples: observation.sensorSamples, time: observation.time)
        switch output {
        case .driveIntents(let drives, let corrections):
            return .driveIntents(drives, corrections: corrections)
        case .actuatorValues(let values):
            return .actuatorValues(values)
        }
    }
}
