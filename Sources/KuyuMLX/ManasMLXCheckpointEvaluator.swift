import Foundation
import KuyuCore
import KuyuPhysics
import KuyuScenarios
import KuyuTraining

public struct ManasMLXCheckpointEvaluatorConfig: Sendable, Equatable {
    public let descriptorPath: String
    public let determinism: DeterminismConfig
    public let schedule: SimulationSchedule
    public let gains: ImuRateDampingCutGains
    public let useQualityGating: Bool

    public init(
        descriptorPath: String,
        determinism: DeterminismConfig,
        schedule: SimulationSchedule,
        gains: ImuRateDampingCutGains,
        useQualityGating: Bool
    ) {
        self.descriptorPath = descriptorPath
        self.determinism = determinism
        self.schedule = schedule
        self.gains = gains
        self.useQualityGating = useQualityGating
    }
}

public enum ManasMLXCheckpointEvaluatorError: Error, Sendable, Equatable {
    case missingTaskQualityDefinition(scenarioID: String, seed: UInt64)
    case missingTaskQualityLog(scenarioID: String, seed: UInt64)
    case unexpectedTaskQualityLog(scenarioID: String, seed: UInt64)
    case duplicateTaskQualityLog(scenarioID: String, seed: UInt64)
    case rolloutOutputCountMismatch(expected: Int, actual: Int)
    case rolloutOutputScenarioMismatch(expectedScenarioID: String, actualScenarioID: String, expectedSeed: UInt64, actualSeed: UInt64)
}

@MainActor
public struct ManasMLXCheckpointEvaluator: CheckpointEvaluating {
    private let config: ManasMLXCheckpointEvaluatorConfig

    public init(config: ManasMLXCheckpointEvaluatorConfig) {
        self.config = config
    }

    public func evaluateCheckpoint(request: CheckpointEvaluationRequest) async throws -> CheckpointEvaluationArtifact {
        _ = try ManasMLXE2EPreflight().check(
            descriptorPath: config.descriptorPath,
            sourceCheckpointURL: request.checkpointURL
        )
        let parameters = try loadParameters(
            modelPath: config.descriptorPath,
            task: request.profile.task
        )
        let descriptor = try loadDescriptor(modelPath: config.descriptorPath)
        let taskMode = try taskMode(from: request.profile.task)
        let evaluationDefinitions = try definitions(profile: request.profile, taskMode: taskMode)
        let outputs = try await runEvaluationOutputs(
            request: request,
            taskMode: taskMode,
            parameters: parameters,
            descriptor: descriptor,
            definitions: evaluationDefinitions
        )
        let teacherOutput = outputs.teacher
        let policyOutput = outputs.policy
        let teacher = TrainingProbeRunSummary(stage: .teacherBaseline, output: teacherOutput)
        let policy = TrainingProbeRunSummary(stage: .initialPolicy, output: policyOutput)
        let quality = try taskQuality(definitions: evaluationDefinitions, output: policyOutput)
        let diagnostics = CheckpointEvaluationDiagnostics(teacher: teacherOutput, policy: policyOutput)
        let artifact = CheckpointEvaluationArtifact(
            evaluationID: request.evaluationID,
            startedAt: Date(),
            profile: request.profile,
            checkpointURL: request.checkpointURL,
            teacher: teacher,
            policy: policy,
            expectedQualityKeys: quality.expectedKeys,
            qualitySummary: quality.summaries,
            diagnostics: diagnostics
        )
        try write(
            artifact: artifact,
            teacher: teacher,
            policy: policy,
            diagnostics: diagnostics,
            to: request.artifactRoot
        )
        return artifact
    }

    private func runEvaluationOutputs(
        request: CheckpointEvaluationRequest,
        taskMode: SimulationTaskMode,
        parameters: ReferenceQuadrotorParameters,
        descriptor: RobotDescriptor?,
        definitions: [ReferenceQuadrotorScenarioDefinition]
    ) async throws -> (teacher: KuyAtt1RunOutput, policy: KuyAtt1RunOutput) {
        guard taskMode == .lift || taskMode == .singleLift else {
            let teacherRequest = SimulationRunRequest(
                controller: .teacherBaseline,
                taskMode: taskMode,
                gains: config.gains,
                cutPeriodSteps: config.schedule.cut.periodSteps,
                noise: .zero,
                determinism: config.determinism,
                modelDescriptorPath: config.descriptorPath,
                overrideParameters: config.descriptorPath.isEmpty ? nil : parameters,
                useAux: true,
                useQualityGating: config.useQualityGating
            )
            let store = ManasMLXModelStore()
            let runtime = KuyuScenarioRuntime(modelStore: store)
            let teacherOutput = try await runtime.run(
                request: teacherRequest,
                parameters: parameters,
                schedule: config.schedule,
                descriptor: descriptor,
                definitions: definitions,
                control: nil
            )
            let manifest = try store.loadModel(from: request.checkpointURL)
            let policyRequest = SimulationRunRequest(
                controller: .manasMLX,
                taskMode: taskMode,
                gains: config.gains,
                cutPeriodSteps: config.schedule.cut.periodSteps,
                noise: .zero,
                determinism: config.determinism,
                modelDescriptorPath: config.descriptorPath,
                overrideParameters: config.descriptorPath.isEmpty ? nil : parameters,
                useAux: manifest.coreConfig.auxEnabled,
                useQualityGating: config.useQualityGating
            )
            let policyOutput = try await store.runManasMLX(
                parameters: parameters,
                schedule: config.schedule,
                request: policyRequest,
                descriptor: descriptor,
                definitions: definitions,
                control: nil
            )
            return (teacherOutput, policyOutput)
        }

        let teacherOutput = try await rolloutOutput(
            definitions: definitions,
            parameters: parameters,
            policyFactory: KuyAtt1BaselinePolicyFactory(
                parameters: parameters,
                gains: config.gains,
                mode: .teacher
            ),
            profile: request.profile,
            controllerRawValue: "Teacher Baseline",
            descriptor: descriptor
        )
        let policyOutput = try await rolloutOutput(
            definitions: definitions,
            parameters: parameters,
            policyFactory: ManasMLXRolloutPolicyFactory(
                snapshotDirectory: request.checkpointURL,
                policyID: "manasMLX-checkpoint-evaluation"
            ),
            profile: request.profile,
            controllerRawValue: "manasMLX",
            descriptor: descriptor
        )
        return (teacherOutput, policyOutput)
    }

    private func rolloutOutput(
        definitions: [ReferenceQuadrotorScenarioDefinition],
        parameters: ReferenceQuadrotorParameters,
        policyFactory: any ReferenceQuadrotorPolicyFactory,
        profile: TaskEvaluationProfile,
        controllerRawValue: String,
        descriptor: RobotDescriptor?
    ) async throws -> KuyAtt1RunOutput {
        let motorSettings = profile.motorNerveSettings(controllerRawValue: controllerRawValue)
        let runner = RolloutRunner(
            parameters: parameters,
            schedule: config.schedule,
            determinism: config.determinism,
            noise: .zero,
            hoverThrustScale: config.gains.hoverThrustScale,
            descriptorId: descriptor?.robot.robotID,
            motorNerveRateLimitPerSecond: motorSettings.rateLimitPerSecond,
            motorNerveSmoothingTimeConstant: motorSettings.smoothingTimeConstant
        )
        let episodes = try await runner.run(
            definitions: definitions,
            policyFactory: policyFactory
        )
        guard episodes.count == definitions.count else {
            throw ManasMLXCheckpointEvaluatorError.rolloutOutputCountMismatch(
                expected: definitions.count,
                actual: episodes.count
            )
        }
        let logs = try zip(definitions, episodes).map { definition, episode in
            try logEntry(definition: definition, episode: episode)
        }
        let evaluations = zip(definitions, logs).map { definition, entry in
            ReferenceQuadrotorScenarioEvaluator().evaluate(definition: definition, log: entry.log)
        }
        let manifest = ReferenceQuadrotorScenarioManifestBuilder().build(from: definitions)
        let result = SuiteRunResult(
            evaluations: evaluations,
            replayChecks: [],
            passed: evaluations.allSatisfy { $0.passed }
        )
        let aggregate = EvaluationAggregate.from(evaluations: result.evaluations)
        let summary = ValidationSummary(
            suitePassed: result.passed,
            evaluations: result.evaluations,
            replayChecks: result.replayChecks,
            manifest: manifest,
            aggregate: aggregate
        )
        return KuyAtt1RunOutput(result: result, summary: summary, logs: logs)
    }

    private func logEntry(
        definition: ReferenceQuadrotorScenarioDefinition,
        episode: RolloutEpisode
    ) throws -> ScenarioLogEntry {
        guard definition.config.id.rawValue == episode.scenarioId,
              definition.config.seed.rawValue == episode.seed else {
            throw ManasMLXCheckpointEvaluatorError.rolloutOutputScenarioMismatch(
                expectedScenarioID: definition.config.id.rawValue,
                actualScenarioID: episode.scenarioId,
                expectedSeed: definition.config.seed.rawValue,
                actualSeed: episode.seed
            )
        }
        let scenarioID = try ScenarioID(episode.scenarioId)
        let seed = ScenarioSeed(episode.seed)
        let failureReason = episode.failureReason.flatMap(FailureReason.init(rawValue:))
        let log = SimulationLog(
            scenarioId: scenarioID,
            seed: seed,
            timeStep: definition.config.timeStep,
            determinism: config.determinism,
            configHash: episode.configHash,
            events: episode.steps.map(\.log),
            failureReason: failureReason,
            failureTime: episode.failureTime
        )
        return ScenarioLogEntry(
            key: ScenarioKey(scenarioId: scenarioID, seed: seed),
            log: log
        )
    }

    private func write(
        artifact: CheckpointEvaluationArtifact,
        teacher: TrainingProbeRunSummary,
        policy: TrainingProbeRunSummary,
        diagnostics: CheckpointEvaluationDiagnostics,
        to root: URL
    ) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(teacher).write(
            to: root.appendingPathComponent("teacher-run.json"),
            options: [.atomic]
        )
        try encoder.encode(policy).write(
            to: root.appendingPathComponent("policy-run.json"),
            options: [.atomic]
        )
        try encoder.encode(diagnostics).write(
            to: root.appendingPathComponent("checkpoint-evaluation-diagnostics.json"),
            options: [.atomic]
        )
        try encoder.encode(artifact).write(
            to: root.appendingPathComponent(CheckpointEvaluationArtifact.fileName),
            options: [.atomic]
        )
    }

    private func taskQuality(
        definitions: [ReferenceQuadrotorScenarioDefinition],
        output: KuyAtt1RunOutput
    ) throws -> (expectedKeys: [CheckpointEvaluationScenarioKey], summaries: [ReferenceQuadrotorTaskQualitySummary]) {
        let definitionByKey = Dictionary(uniqueKeysWithValues: definitions.map { definition in
            (key(scenarioID: definition.config.id.rawValue, seed: definition.config.seed.rawValue), definition)
        })
        let expectedKeys = definitions.map { definition in
            CheckpointEvaluationScenarioKey(
                scenarioID: definition.config.id.rawValue,
                seed: definition.config.seed.rawValue
            )
        }
        let evaluator = ReferenceQuadrotorTaskQualityEvaluator()
        var summaries: [ReferenceQuadrotorTaskQualitySummary] = []
        var actualKeys = Set<CheckpointEvaluationScenarioKey>()
        for entry in output.logs {
            let qualityKey = CheckpointEvaluationScenarioKey(
                scenarioID: entry.key.scenarioId.rawValue,
                seed: entry.key.seed.rawValue
            )
            guard actualKeys.insert(qualityKey).inserted else {
                throw ManasMLXCheckpointEvaluatorError.duplicateTaskQualityLog(
                    scenarioID: qualityKey.scenarioID,
                    seed: qualityKey.seed
                )
            }
            let entryKey = key(
                scenarioID: entry.key.scenarioId.rawValue,
                seed: entry.key.seed.rawValue
            )
            guard let definition = definitionByKey[entryKey] else {
                throw ManasMLXCheckpointEvaluatorError.missingTaskQualityDefinition(
                    scenarioID: entry.key.scenarioId.rawValue,
                    seed: entry.key.seed.rawValue
                )
            }
            summaries.append(evaluator.evaluate(definition: definition, log: entry.log))
        }
        let expectedSet = Set(expectedKeys)
        let missing = expectedSet.subtracting(actualKeys).sorted()
        if let first = missing.first {
            throw ManasMLXCheckpointEvaluatorError.missingTaskQualityLog(
                scenarioID: first.scenarioID,
                seed: first.seed
            )
        }
        let unexpected = actualKeys.subtracting(expectedSet).sorted()
        if let first = unexpected.first {
            throw ManasMLXCheckpointEvaluatorError.unexpectedTaskQualityLog(
                scenarioID: first.scenarioID,
                seed: first.seed
            )
        }
        return (expectedKeys, summaries)
    }

    private func key(scenarioID: String, seed: UInt64) -> String {
        "\(scenarioID)#\(seed)"
    }

    private func definitions(
        profile: TaskEvaluationProfile,
        taskMode: SimulationTaskMode
    ) throws -> [ReferenceQuadrotorScenarioDefinition] {
        let baseDefinitions = try baseDefinitions(taskMode: taskMode)
        guard taskMode == .lift || taskMode == .singleLift else {
            return baseDefinitions
        }
        return try profile.baseEvaluationSuiteIDs.flatMap { suiteID in
            guard suiteID != 1 else {
                return baseDefinitions
            }
            return try makeLiftSuiteDefinitions(
                taskMode: taskMode,
                suite: suiteID,
                baseDefinitions: baseDefinitions
            )
        }
    }

    private func baseDefinitions(taskMode: SimulationTaskMode) throws -> [ReferenceQuadrotorScenarioDefinition] {
        switch taskMode {
        case .attitude:
            return try KuyAtt1Suite().scenarios()
        case .lift:
            return try KuyLiftSuite().scenarios()
        case .singleLift:
            return try KuySingleLiftSuite().scenarios()
        }
    }

    private func makeLiftSuiteDefinitions(
        taskMode: SimulationTaskMode,
        suite: Int,
        baseDefinitions: [ReferenceQuadrotorScenarioDefinition]
    ) throws -> [ReferenceQuadrotorScenarioDefinition] {
        try baseDefinitions.enumerated().map { index, definition in
            try liftSuiteDefinition(
                taskMode: taskMode,
                suite: suite,
                index: index,
                definition: definition
            )
        }
    }

    private func liftSuiteDefinition(
        taskMode: SimulationTaskMode,
        suite: Int,
        index: Int,
        definition: ReferenceQuadrotorScenarioDefinition
    ) throws -> ReferenceQuadrotorScenarioDefinition {
        guard let liftEnvelope = definition.liftEnvelope else {
            return definition
        }

        let isSingleLift = taskMode == .singleLift
        let targetOffset: Double
        let actuatorDegradation: ActuatorDegradation?
        let torqueEvents: [TorqueDisturbanceEvent]
        let hfEvents: [HFStressEvent]
        switch suite {
        case 6:
            targetOffset = 0
            actuatorDegradation = definition.actuatorDegradation
            torqueEvents = definition.torqueEvents
            hfEvents = definition.hfEvents
        case 7:
            targetOffset = isSingleLift ? 0.02 : 0.05
            actuatorDegradation = definition.actuatorDegradation
            torqueEvents = definition.torqueEvents
            hfEvents = definition.hfEvents
        case 8:
            targetOffset = isSingleLift ? -0.01 : -0.02
            actuatorDegradation = definition.actuatorDegradation
            torqueEvents = definition.torqueEvents + [
                try TorqueDisturbanceEvent(
                    startTime: max(0.75, definition.config.duration * 0.35),
                    duration: 0.05,
                    torqueBody: Axis3(x: isSingleLift ? 0.0002 : 0.0005, y: 0, z: 0)
                ),
            ]
            hfEvents = definition.hfEvents + [
                try HFStressEvent(
                    kind: .latencySpike,
                    startTime: max(1.0, definition.config.duration * 0.50),
                    duration: 0.01,
                    magnitude: 0.01
                ),
            ]
        default:
            throw TaskEvaluationProfileError.unsupportedTask("suite-\(suite)")
        }

        let targetZ = max(0.05, liftEnvelope.targetZ + targetOffset)
        let adjustedLiftEnvelope = LiftEnvelope(
            targetZ: targetZ,
            tolerance: liftEnvelope.tolerance,
            maxVelocity: liftEnvelope.maxVelocity,
            warmupTime: liftEnvelope.warmupTime,
            requiredHoldTime: liftEnvelope.requiredHoldTime
        )
        let prefix = isSingleLift ? "KUY-SLIFT-M2-S\(suite)" : "KUY-LIFT-M2-S\(suite)"

        return ReferenceQuadrotorScenarioDefinition(
            config: try ScenarioConfig(
                id: try ScenarioID("\(prefix)/SCN-\(index + 1)"),
                seed: ScenarioSeed(definition.config.seed.rawValue &+ UInt64(suite * 10_000 + index)),
                duration: definition.config.duration,
                timeStep: definition.config.timeStep
            ),
            kind: definition.kind,
            initialPosition: Axis3(
                x: definition.initialPosition.x,
                y: definition.initialPosition.y,
                z: targetZ
            ),
            initialAttitude: definition.initialAttitude,
            initialAngularVelocity: definition.initialAngularVelocity,
            safetyEnvelope: definition.safetyEnvelope,
            liftEnvelope: adjustedLiftEnvelope,
            torqueEvents: torqueEvents,
            actuatorDegradation: actuatorDegradation,
            gyroDriftScale: suite == 8 ? max(definition.gyroDriftScale, 1.5) : definition.gyroDriftScale,
            swapEvents: definition.swapEvents,
            hfEvents: hfEvents
        )
    }

    private func taskMode(from task: String) throws -> SimulationTaskMode {
        switch task {
        case "attitude":
            return .attitude
        case "lift":
            return .lift
        case "singleLift":
            return .singleLift
        default:
            throw TaskEvaluationProfileError.unsupportedTask(task)
        }
    }

    private func loadParameters(modelPath: String, task: String) throws -> ReferenceQuadrotorParameters {
        let trimmed = modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return try tunedParametersIfNeeded(
                parameters: .baseline,
                task: task
            )
        }

        let loader = RobotDescriptorLoader()
        let descriptor = try loader.loadDescriptor(path: trimmed)
        let inertial = try loader.loadPlantInertialProperties(descriptor: descriptor)
        let parameters = try ReferenceQuadrotorParameters.reference(
            from: inertial,
            robotID: descriptor.descriptor.robot.robotID
        )
        return try tunedParametersIfNeeded(
            parameters: parameters,
            task: task
        )
    }

    private func tunedParametersIfNeeded(
        parameters: ReferenceQuadrotorParameters,
        task: String
    ) throws -> ReferenceQuadrotorParameters {
        guard task == "singleLift" else { return parameters }
        return try KuyuSingleLiftParameterTuning.tuned(
            parameters: parameters,
            hoverThrustScale: config.gains.hoverThrustScale
        )
    }

    private func loadDescriptor(modelPath: String) throws -> RobotDescriptor? {
        let trimmed = modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let loader = RobotDescriptorLoader()
        let descriptor = try loader.loadDescriptor(path: trimmed)
        return descriptor.descriptor
    }
}
