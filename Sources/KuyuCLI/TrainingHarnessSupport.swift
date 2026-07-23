import ArgumentParser
import Foundation
import KuyuCore
import KuyuMLX
import KuyuMLXReferenceQuadrotor
import KuyuMLXTrainingProbe
import KuyuPhysics
import KuyuScenarios
import KuyuTraining
import ManasCore

func selectedCandidateCheckpointURL(_ comparison: TrainingProbeComparison) -> URL? {
    guard comparison.selectedCheckpointRole == .candidate else {
        return nil
    }
    return comparison.selectedCheckpointURL
}

func sourceCheckpointURL(from rawPath: String?) -> URL? {
    guard let rawPath else {
        return nil
    }
    let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return nil
    }
    return URL(fileURLWithPath: trimmed, isDirectory: true)
}

struct CheckTrainingHarnessSummary: Codable {
    let artifactRoot: String
    let environmentReady: Bool
    let probes: [CheckTrainingHarnessProbeEntry]
    let selectedCandidate: ReferenceQuadrotorTrainingHarnessSelectedCandidate?
    let allPassed: Bool
}

struct CheckTrainingHarnessSweepSummary: Codable {
    let artifactRoot: String
    let startedAt: Date
    let environmentReady: Bool
    let requirement: String
    let tasks: [String]
    let seedCount: Int
    let attemptsPerSeed: Int
    let successCount: Int
    let successRate: Double
    let minSuccessRate: Double
    let allPassed: Bool
    let seeds: [CheckTrainingHarnessSeedEntry]
}

struct CheckTrainingHarnessSeedEntry: Codable {
    let seedBase: UInt64
    let successful: Bool
    let acceptedAttempts: [String: Int]
    let finalScoreDelta: Double?
    let finalTrainedScore: Double?
    let finalFailureReasons: [String]
    let probes: [CheckTrainingHarnessProbeEntry]
}

struct CheckTrainingHarnessProbeEntry: Codable {
    let task: String
    let attempt: Int
    let accepted: Bool
    let artifactPath: String
    let terminalState: String
    let trainingCheckpoint: String
    let probeCheckpoint: String
    let selectedCheckpointRole: String
    let selectedCheckpointPath: String?
    let repairSourceCheckpointPath: String?
    let reloadSucceeded: Bool
    let teacherScore: Double
    let initialScore: Double
    let trainedScore: Double?
    let scoreDelta: Double?
    let policySatisfied: Bool
    let harnessSatisfied: Bool
    let taskSolved: Bool
    let trainedFailureReasons: [String]
    let trainedAverageDriveActivation: Double?
    let teacherAverageDriveActivation: Double?
    let trainedAverageDriveActivationByIndex: [Double]?
    let teacherAverageDriveActivationByIndex: [Double]?
    let trainedAverageMotorFinalOutputByIndex: [Double]?
    let trainedFinalAltitudeZ: Double?
    let trainedFinalVerticalVelocityZ: Double?
    let metricsCount: Int
    let recoveryRelabelAttempted: Bool
    let recoveryRelabelDatasetPath: String?
    let recoveryRelabelEntryCount: Int?
    let recoveryRelabelCutStepCount: Int?
    let gateReport: TrainingHarnessGateReport
    let postRegression: ReferenceQuadrotorPostTrainingRegressionEntry?

    var harnessSelectionInput: ReferenceQuadrotorTrainingHarnessProbeSelectionInput {
        ReferenceQuadrotorTrainingHarnessProbeSelectionInput(
            task: task,
            attempt: attempt,
            artifactPath: artifactPath,
            accepted: accepted,
            selectedCheckpointRole: TrainingProbeComparison.SelectedCheckpointRole(
                rawValue: selectedCheckpointRole
            ) ?? .none,
            selectedCheckpointPath: selectedCheckpointPath,
            score: trainedScore,
            scoreDelta: scoreDelta
        )
    }
}

@MainActor
func runCLIManasProbe(
    task: RolloutTaskChoice,
    tier: TierChoice,
    cutPeriodSteps: UInt64,
    model: String,
    sourceCheckpointURL: URL?,
    artifactRoot: URL,
    iterations: Int,
    sequenceLength: Int,
    epochs: Int,
    learningRate: Double,
    maxBatches: Int?,
    workers: Int,
    minDelta: Double,
    kp: Double,
    kd: Double,
    yawDamping: Double,
    hoverScale: Double,
    useAux: Bool,
    useQualityGating: Bool,
    mlxSeed: UInt64?,
    additionalDatasetURLs: [URL] = [],
    additionalDatasetRepeatCount: Int = 1,
    printEvents: Bool
) async throws -> TrainingProbeResult {
    if let mlxSeed {
        if printEvents {
            print("[probe] mlxSeed=\(mlxSeed)")
        }
    }
    let preflight = try ManasMLXRuntimeReadinessService().report(
        for: ManasMLXRuntimeReadinessRequest(
            robotManifestPath: model,
            sourceCheckpointURL: sourceCheckpointURL
        )
    )
    if printEvents {
        print("[probe] preflight mlx=\(preflight.mlxRuntimeReady) robotManifestLoaded=\(preflight.robotManifestLoaded) sourceCheckpointLoadable=\(preflight.sourceCheckpointLoadable)")
        if !additionalDatasetURLs.isEmpty {
            print("[probe] additionalDatasets=\(additionalDatasetURLs.map(\.path).joined(separator: ","))")
        }
    }

    let determinism = try makeDeterminism(tier: tier)
    let schedule = try SimulationSchedule.baseline(cutPeriodSteps: cutPeriodSteps)
    let parameters = try loadParameters(modelPath: model)
    let embodiment = try loadEmbodiment(modelPath: model)
    let gains = try ImuRateDampingCutGains(
        kp: kp,
        kd: kd,
        yawDamping: yawDamping,
        hoverThrustScale: hoverScale
    )
    let taskMode = simulationTaskMode(from: task)
    let runID = "probe-\(UUID().uuidString)"
    let teacherRequest = SimulationRunRequest(
        controller: .teacherActiveAltitudeHold,
        taskMode: taskMode,
        gains: gains,
        cutPeriodSteps: cutPeriodSteps,
        noise: .zero,
        determinism: determinism,
        robotManifestPath: model,
        overrideParameters: model.isEmpty ? nil : parameters,
        useAux: useAux,
        useQualityGating: useQualityGating
    )
    let trainingRequest = SimulationRunRequest(
        controller: .manasMLX,
        taskMode: taskMode,
        gains: gains,
        cutPeriodSteps: cutPeriodSteps,
        noise: .zero,
        determinism: determinism,
        robotManifestPath: model,
        overrideParameters: model.isEmpty ? nil : parameters,
        useAux: useAux,
        useQualityGating: useQualityGating
    )

    return try await ManasMLXTrainingProbeService().run(
        request: ManasMLXTrainingProbeRequest(
            probeID: runID,
            teacherRequest: teacherRequest,
            trainingRequest: trainingRequest,
            parameters: parameters,
            schedule: schedule,
            embodiment: embodiment,
            sourceCheckpointURL: sourceCheckpointURL,
            artifactRoot: artifactRoot,
            iterations: iterations,
            sequenceLength: sequenceLength,
            epochs: epochs,
            learningRate: learningRate,
            maxBatches: maxBatches,
            workerCount: workers,
            minScoreDelta: minDelta,
            additionalDatasetURLs: additionalDatasetURLs,
            additionalDatasetRepeatCount: additionalDatasetRepeatCount,
            mlxSeed: mlxSeed
        )
    ) { event in
        guard printEvents else { return }
        switch event {
        case .stageStarted(let stage, _):
            print("[probe] stage=\(stage.rawValue) started")
        case .stageCompleted(let summary, _):
            print("[probe] stage=\(summary.stage.rawValue) completed score=\(String(format: "%.3f", summary.score))")
        case .stageFailed(let stage, let reason, _):
            print("[probe] stage=\(stage.rawValue) failed reason=\(reason)")
        case .training(.iterationStarted(let iteration)):
            print("[probe] training iter=\(iteration) started")
        case .training(.suiteCompleted(let iteration, _, let score)):
            print("[probe] training iter=\(iteration) teacherDatasetScore=\(String(format: "%.3f", score))")
        case .training(.datasetExported(let iteration, let directory, let count)):
            print("[probe] training iter=\(iteration) dataset count=\(count) path=\(directory)")
        case .training(.trainingCompleted(let iteration, let backendResult)):
            print("[probe] training iter=\(iteration) loss=\(String(format: "%.6f", backendResult.finalLoss))")
        case .training(.convergenceUpdated(let summary)):
            print("[probe] convergence accepted=\(summary.accepted) reason=\(summary.reason)")
        case .training:
            break
        }
    }
}

func parseProbeTasks(_ raw: String) throws -> [RolloutTaskChoice] {
    let parts = raw
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    guard !parts.isEmpty else {
        throw ValidationError("--tasks must include at least one task.")
    }
    var tasks: [RolloutTaskChoice] = []
    for part in parts {
        guard let task = RolloutTaskChoice(rawValue: part) else {
            throw ValidationError("Unsupported task '\(part)'. Use attitude, lift, or singleLift.")
        }
        if !tasks.contains(task) {
            tasks.append(task)
        }
    }
    return tasks
}

@MainActor
struct CLIScenarioExecutor: TrainingScenarioExecuting {
    let store: ManasMLXModelStore
    let parameters: ReferenceQuadrotorParameters
    let schedule: SimulationSchedule
    let embodiment: EmbodimentContract?

    func runSuiteForTrainingRun(request: SimulationRunRequest) async throws -> TrainingScenarioRunOutput {
        let output = try await store.runReferenceQuadrotor(
            parameters: parameters,
            schedule: schedule,
            request: request,
            embodiment: embodiment,
            control: nil
        )
        return TrainingScenarioRunOutput(kuyAtt1: output)
    }
}
