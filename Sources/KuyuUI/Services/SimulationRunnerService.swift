import KuyuCore
import KuyuMLX
import Logging
import KuyuPhysics
import KuyuScenarios

public struct SimulationRunnerService: Sendable {
    let modelStore: ManasMLXModelStore
    let manualActuatorStore: ManualActuatorStore?
    private var logger: Logger

    public init(
        modelStore: ManasMLXModelStore,
        manualActuatorStore: ManualActuatorStore? = nil
    ) {
        self.modelStore = modelStore
        self.manualActuatorStore = manualActuatorStore
        self.logger = Logger(label: "kuyu.ui")
    }

    public func run(
        request: SimulationRunRequest,
        control: SimulationControl? = nil,
        telemetry: WorldStepTelemetry? = nil
    ) async throws -> KuyAtt1RunOutput {
        if let loadedRobot = try loadRobot(request: request),
           isArticulatedDynamicModel(loadedRobot) {
            return try await runArticulatedDynamic(
                request: request,
                loadedRobot: loadedRobot,
                control: control,
                telemetry: telemetry
            )
        }

        let schedule = try SimulationSchedule.baseline(cutPeriodSteps: request.cutPeriodSteps)
        let resolution = try resolveParameters(request: request)
        let parameters = resolution.parameters
        let embodiment = resolution.embodiment
        let starterContract = ReferenceQuadrotorStarterCheckpointContractService()
            .defaultContract(for: request.taskMode)
        switch request.controller {
        case .teacherActiveAltitudeHold, .sensorBaseline:
            let baselineMode = request.controller.kuyAtt1BaselineMode ?? .teacher
            if let store = manualActuatorStore, store.isEnabled, request.taskMode != .singleLift {
                return try await runManualBaseline(
                    request: request,
                    parameters: parameters,
                    embodiment: embodiment,
                    schedule: schedule,
                    control: control,
                    telemetry: telemetry,
                    store: store
                )
            }
            if request.taskMode == .lift {
                if let chainFactory = try motorNerveChainFactory(
                    embodiment: embodiment,
                    request: request,
                    expectedDriveCount: starterContract.expectedDriveCount
                ) {
                    return try await runLiftBaselineWithChain(
                        request: request,
                        parameters: parameters,
                        schedule: schedule,
                        control: control,
                        telemetry: telemetry,
                        chainFactory: chainFactory
                    )
                } else {
                    return try await runLiftBaseline(
                        request: request,
                        parameters: parameters,
                        schedule: schedule,
                        control: control,
                        telemetry: telemetry
                    )
                }
            }
            if request.taskMode == .singleLift {
                if let chainFactory = try motorNerveChainFactory(
                    embodiment: embodiment,
                    request: request,
                    expectedDriveCount: starterContract.expectedDriveCount
                ) {
                    return try await runSingleLiftBaselineWithChain(
                        request: request,
                        parameters: parameters,
                        schedule: schedule,
                        control: control,
                        telemetry: telemetry,
                        chainFactory: chainFactory
                    )
                } else {
                    return try await runSingleLiftBaseline(
                        request: request,
                        parameters: parameters,
                        schedule: schedule,
                        control: control,
                        telemetry: telemetry
                    )
                }
            }
            if let chainFactory = try motorNerveChainFactory(
                embodiment: embodiment,
                request: request,
                expectedDriveCount: starterContract.expectedDriveCount
            ) {
                return try await runAttitudeBaselineWithChain(
                    request: request,
                    parameters: parameters,
                    schedule: schedule,
                    control: control,
                    telemetry: telemetry,
                    chainFactory: chainFactory,
                    baselineMode: baselineMode
                )
            }
            // Interactive simulation runs do not execute replay verification;
            // the duplicated rollout would double the user-visible latency.
            let runner = KuyAtt1Runner(
                parameters: parameters,
                schedule: schedule,
                determinism: request.determinism,
                noise: request.noise,
                gains: request.gains,
                baselineMode: baselineMode,
                replayVerification: false
            )
            return try await runner.runWithLogs(control: control)
        case .manasMLX:
            try MLXRuntimeReadinessService().check()
            return try await modelStore.runReferenceQuadrotor(
                parameters: parameters,
                schedule: schedule,
                request: request,
                embodiment: embodiment,
                control: control,
                telemetry: telemetry
            )
        }
    }

    private func loadRobot(request: SimulationRunRequest) throws -> LoadedKuyuRobot? {
        let trimmed = request.robotManifestPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        do {
            let loader = KuyuModelLoader()
            return try loader.loadRobot(path: trimmed, worldPath: request.worldModelPath)
        } catch {
            logger.error("Kuyu robot load failed", metadata: [
                "action": "robotManifestLoadFailed",
                "task": .string(request.taskMode.rawValue),
                "model": .string(trimmed),
                "robotManifest": .string(trimmed),
                "worldModel": .string(request.worldModelPath),
                "reason": "loadFailed",
                "error": .string(String(describing: error))
            ])
            throw error
        }
    }

    private func resolveParameters(request: SimulationRunRequest) throws -> SimulationParameterResolution {
        let loadedRobot = try loadRobot(request: request)
        return try loadParameters(request: request, loadedRobot: loadedRobot)
    }

    private func motorNerveChainFactory(
        embodiment: EmbodimentContract?,
        request: SimulationRunRequest,
        expectedDriveCount: Int
    ) throws -> (() throws -> MotorNerveChain)? {
        guard let embodiment else { return nil }
        let modelPath = request.robotManifestPath.trimmingCharacters(in: .whitespacesAndNewlines)

        if embodiment.control.driveChannels.count != expectedDriveCount {
            logger.error("MotorNerveChain rejected due to drive count mismatch", metadata: [
                "action": "motorNerveContractRejected",
                "task": .string(request.taskMode.rawValue),
                "model": .string(modelPath),
                "robotManifest": .string(modelPath),
                "reason": "driveCountMismatch",
                "expectedDriveCount": .string("\(expectedDriveCount)"),
                "actualDriveCount": .string("\(embodiment.control.driveChannels.count)"),
                "motorNerveProfile": "embodiment-contract"
            ])
            throw SimulationRunnerServiceError.motorNerveDriveCountMismatch(
                modelPath: modelPath,
                expected: expectedDriveCount,
                actual: embodiment.control.driveChannels.count
            )
        }

        if let unsupportedStage = embodiment.motorNerve.stages.first(where: { $0.type == .custom }) {
            logger.error("MotorNerveChain rejected due to unsupported stage", metadata: [
                "action": "motorNerveContractRejected",
                "task": .string(request.taskMode.rawValue),
                "model": .string(modelPath),
                "robotManifest": .string(modelPath),
                "reason": "unsupportedCustomStage",
                "stageID": .string(unsupportedStage.id),
                "motorNerveProfile": "embodiment-contract"
            ])
            throw SimulationRunnerServiceError.unsupportedMotorNerveStage(
                modelPath: modelPath,
                stageID: unsupportedStage.id
            )
        }

        logger.notice("MotorNerveChain enabled", metadata: [
            "action": "motorNerveChain",
            "task": .string(request.taskMode.rawValue),
            "model": .string(modelPath),
            "motorNerveProfile": "embodiment-contract"
        ])

        return { try MotorNerveChain(contract: embodiment) }
    }

    private func runAttitudeBaselineWithChain(
        request: SimulationRunRequest,
        parameters: ReferenceQuadrotorParameters,
        schedule: SimulationSchedule,
        control: SimulationControl?,
        telemetry: WorldStepTelemetry?,
        chainFactory: @escaping () throws -> MotorNerveChain,
        baselineMode: KuyAtt1BaselineMode
    ) async throws -> KuyAtt1RunOutput {
        let runner = ReferenceQuadrotorScenarioRunner<ImuRateDampingDriveCut, MotorNerveChain>(
            parameters: parameters,
            schedule: schedule,
            determinism: request.determinism,
            noise: request.noise,
            environment: .standard,
            hoverThrustScale: request.gains.hoverThrustScale
        )

        let validation = KuyAtt1Validation(runner: runner)
        let output = try await validation.runWithLogs(
            cutFactory: { definition in
                let hoverThrust = parameters.mass * parameters.gravity / 4.0 * request.gains.hoverThrustScale
                let initialAttitude: EulerAngles
                let tiltCorrectionTimeConstant: Double?
                switch baselineMode {
                case .teacher:
                    initialAttitude = definition.initialAttitude
                    tiltCorrectionTimeConstant = nil
                case .sensor:
                    initialAttitude = EulerAngles(roll: 0, pitch: 0, yaw: 0)
                    tiltCorrectionTimeConstant = 0.4
                }
                return try ImuRateDampingDriveCut(
                    hoverThrust: hoverThrust,
                    kp: request.gains.kp,
                    kd: request.gains.kd,
                    yawDamping: request.gains.yawDamping,
                    armLength: parameters.armLength,
                    yawCoefficient: parameters.yawCoefficient,
                    maxThrust: parameters.maxThrust,
                    initialRoll: initialAttitude.roll,
                    initialPitch: initialAttitude.pitch,
                    tiltCorrectionTimeConstant: tiltCorrectionTimeConstant
                )
            },
            motorNerveFactory: { _ in
                try chainFactory()
            },
            control: control,
            telemetry: telemetry
        )

        let aggregate = EvaluationAggregate.from(evaluations: output.result.evaluations)
        let summary = ValidationSummary(
            suitePassed: output.result.passed,
            evaluations: output.result.evaluations,
            replay: output.result.replay,
            manifest: output.manifest,
            aggregate: aggregate
        )

        return KuyAtt1RunOutput(result: output.result, summary: summary, logs: output.logs)
    }

    private func runArticulatedDynamic(
        request: SimulationRunRequest,
        loadedRobot: LoadedKuyuRobot,
        control: SimulationControl?,
        telemetry: WorldStepTelemetry?
    ) async throws -> KuyAtt1RunOutput {
        logger.notice("Articulated dynamic simulation enabled", metadata: [
            "action": "articulatedDynamic",
            "task": .string(request.taskMode.rawValue),
            "model": .string(request.robotManifestPath),
            "robotID": .string(loadedRobot.manifest.robotID),
            "readiness": .string(request.readinessRequirement.rawValue),
            "motorNerveProfile": "embodiment-contract"
        ])

        let log = try await ArticulatedRigidBodySimulator().run(
            request: ArticulatedRigidBodySimulationRequest(
                body: loadedRobot.body,
                world: loadedRobot.world,
                embodiment: loadedRobot.embodiment,
                compatibilityReport: loadedRobot.compatibilityReport,
                determinism: request.determinism,
                readinessLevel: request.readinessRequirement,
                duration: 6.0,
                timeStep: try TimeStep(delta: loadedRobot.world.time.fixedStepSeconds)
            ),
            control: control,
            telemetry: telemetry
        )
        return ArticulatedDynamicScenarioOutputFactory().makeOutput(log: log)
    }

    private func isArticulatedDynamicModel(_ loadedRobot: LoadedKuyuRobot) -> Bool {
        let movableJointCount = loadedRobot.body.joints.filter {
            $0.kind == .revolute || $0.kind == .continuous || $0.kind == .prismatic
        }.count
        return (loadedRobot.manifest.category == "manipulator" || loadedRobot.body.category == "manipulator")
            && movableJointCount > 0
    }

    private func loadParameters(
        request: SimulationRunRequest,
        loadedRobot: LoadedKuyuRobot?
    ) throws -> SimulationParameterResolution {
        let service = ReferenceQuadrotorParameterResolutionService()
        do {
            let resolution = try service.resolve(
                ReferenceQuadrotorParameterResolutionRequest(
                    taskMode: request.taskMode,
                    hoverThrustScale: request.gains.hoverThrustScale,
                    loadedRobot: loadedRobot,
                    overrideParameters: request.overrideParameters,
                    robotManifestPath: request.robotManifestPath
                )
            )
            return SimulationParameterResolution(resolution)
        } catch ReferenceQuadrotorParameterResolutionError.robotManifestNotLoaded(let modelPath) {
            logger.error("EmbodimentContract parameters unavailable", metadata: [
                "action": "robotManifestParametersFailed",
                "task": .string(request.taskMode.rawValue),
                "model": .string(modelPath),
                "robotManifest": .string(modelPath),
                "reason": "robotManifestNotLoaded",
                "error": "robotManifestNotLoaded"
            ])
            throw SimulationRunnerServiceError.robotManifestParametersUnavailable(modelPath)
        } catch {
            if loadedRobot != nil {
                logger.error("EmbodimentContract inertial load failed", metadata: [
                    "action": "robotManifestParametersFailed",
                    "task": .string(request.taskMode.rawValue),
                    "model": .string(request.robotManifestPath),
                    "robotManifest": .string(request.robotManifestPath),
                    "reason": "inertialLoadFailed",
                    "error": .string(String(describing: error))
                ])
            }
            throw error
        }
    }

    private func runManualBaseline(
        request: SimulationRunRequest,
        parameters: ReferenceQuadrotorParameters,
        embodiment: EmbodimentContract?,
        schedule: SimulationSchedule,
        control: SimulationControl?,
        telemetry: WorldStepTelemetry?,
        store: ManualActuatorStore
    ) async throws -> KuyAtt1RunOutput {
        let runner = ReferenceQuadrotorScenarioRunner<ImuRateDampingDriveCut, ManualMotorNerve>(
            parameters: parameters,
            schedule: schedule,
            determinism: request.determinism,
            noise: request.noise,
            environment: .standard,
            hoverThrustScale: request.gains.hoverThrustScale
        )

        let definitions = try referenceQuadrotorScenarioDefinitions(for: request.taskMode)
        let manifest = ReferenceQuadrotorScenarioManifestBuilder().build(from: definitions)
        var evaluations: [ScenarioEvaluation] = []
        var logs: [ScenarioLogEntry] = []

        for definition in definitions {
            if let control {
                try await control.checkpoint()
            }
            let cut = try ImuRateDampingDriveCut(
                hoverThrust: parameters.mass * parameters.gravity / 4.0 * request.gains.hoverThrustScale,
                kp: request.gains.kp,
                kd: request.gains.kd,
                yawDamping: request.gains.yawDamping,
                armLength: parameters.armLength,
                yawCoefficient: parameters.yawCoefficient,
                maxThrust: parameters.maxThrust,
                initialRoll: definition.initialAttitude.roll,
                initialPitch: definition.initialAttitude.pitch,
                tiltCorrectionTimeConstant: nil
            )
            let channelMaxima = manualActuatorChannelMaxima(
                embodiment: embodiment,
                fallback: parameters.maxThrust,
                expectedCount: 4
            )
            let log = try await runner.runScenario(
                definition: definition,
                cut: cut,
                motorNerve: ManualMotorNerve(store: store, channelMaxima: channelMaxima),
                control: control,
                telemetry: telemetry
            )
            let key = ScenarioKey(scenarioId: definition.config.id, seed: definition.config.seed)
            logs.append(ScenarioLogEntry(key: key, log: log))
            let evaluation = ReferenceQuadrotorScenarioEvaluator().evaluate(definition: definition, log: log)
            evaluations.append(evaluation)
        }

        let result = SuiteRunResultFactory().makeEvaluationOnly(
            evaluations: evaluations,
            replaySkippedReason: "Interactive simulation runs do not execute replay verification."
        )
        let aggregate = EvaluationAggregate.from(evaluations: result.evaluations)
        let summary = ValidationSummary(
            suitePassed: result.passed,
            evaluations: result.evaluations,
            replay: result.replay,
            manifest: manifest,
            aggregate: aggregate
        )

        return KuyAtt1RunOutput(result: result, summary: summary, logs: logs)
    }

    private func manualActuatorChannelMaxima(
        embodiment: EmbodimentContract?,
        fallback: Double,
        expectedCount: Int
    ) -> [Double] {
        let safeFallback = max(fallback, 0.0)
        var maxima = Array(repeating: safeFallback, count: max(expectedCount, 1))

        guard let embodiment else { return maxima }

        let sortedSignals = embodiment.signals.actuator.sorted { $0.index < $1.index }
        let count = min(expectedCount, sortedSignals.count)
        if count > 0 {
            for index in 0..<count {
                if let range = sortedSignals[index].range {
                    let candidate = max(abs(range.min), abs(range.max))
                    if candidate > 0 {
                        maxima[index] = candidate
                    }
                }
            }
        }

        var limitsBySignalID: [String: Double] = [:]
        for actuator in embodiment.actuators {
            for channelID in actuator.channels {
                let existing = limitsBySignalID[channelID] ?? 0.0
                limitsBySignalID[channelID] = max(existing, actuator.limits.max)
            }
        }

        if count > 0 {
            for index in 0..<count {
                let signalID = sortedSignals[index].id
                if let limit = limitsBySignalID[signalID], limit > 0 {
                    maxima[index] = limit
                }
            }
        }

        return maxima
    }

    private func referenceQuadrotorScenarioDefinitions(
        for taskMode: SimulationTaskMode
    ) throws -> [ReferenceQuadrotorScenarioDefinition] {
        try ReferenceQuadrotorRolloutScenarioDefinitionFactory().scenarios(taskMode: taskMode)
    }

    private func runLiftBaseline(
        request: SimulationRunRequest,
        parameters: ReferenceQuadrotorParameters,
        schedule: SimulationSchedule,
        control: SimulationControl?,
        telemetry: WorldStepTelemetry?
    ) async throws -> KuyAtt1RunOutput {
        let runner = ReferenceQuadrotorScenarioRunner<ImuRateDampingDriveCut, LiftMotorNerve>(
            parameters: parameters,
            schedule: schedule,
            determinism: request.determinism,
            noise: request.noise,
            environment: .standard,
            hoverThrustScale: request.gains.hoverThrustScale
        )

        let definitions = try referenceQuadrotorScenarioDefinitions(for: .lift)
        let manifest = ReferenceQuadrotorScenarioManifestBuilder().build(from: definitions)
        var evaluations: [ScenarioEvaluation] = []
        var logs: [ScenarioLogEntry] = []

        for definition in definitions {
            if let control {
                try await control.checkpoint()
            }
            let cut = try ImuRateDampingDriveCut(
                hoverThrust: parameters.mass * parameters.gravity / 4.0 * request.gains.hoverThrustScale,
                kp: request.gains.kp,
                kd: request.gains.kd,
                yawDamping: request.gains.yawDamping,
                armLength: parameters.armLength,
                yawCoefficient: parameters.yawCoefficient,
                maxThrust: parameters.maxThrust,
                initialRoll: definition.initialAttitude.roll,
                initialPitch: definition.initialAttitude.pitch,
                tiltCorrectionTimeConstant: nil
            )
            let maxThrusts = try MotorMaxThrusts.uniform(parameters.maxThrust)
            let log = try await runner.runScenario(
                definition: definition,
                cut: cut,
                motorNerve: LiftMotorNerve(motorMaxThrusts: maxThrusts),
                control: control,
                telemetry: telemetry
            )
            let key = ScenarioKey(scenarioId: definition.config.id, seed: definition.config.seed)
            logs.append(ScenarioLogEntry(key: key, log: log))
            let evaluation = ReferenceQuadrotorScenarioEvaluator().evaluate(definition: definition, log: log)
            evaluations.append(evaluation)
        }

        let result = SuiteRunResultFactory().makeEvaluationOnly(
            evaluations: evaluations,
            replaySkippedReason: "Interactive simulation runs do not execute replay verification."
        )
        let aggregate = EvaluationAggregate.from(evaluations: result.evaluations)
        let summary = ValidationSummary(
            suitePassed: result.passed,
            evaluations: result.evaluations,
            replay: result.replay,
            manifest: manifest,
            aggregate: aggregate
        )

        return KuyAtt1RunOutput(result: result, summary: summary, logs: logs)
    }

    private func runLiftBaselineWithChain(
        request: SimulationRunRequest,
        parameters: ReferenceQuadrotorParameters,
        schedule: SimulationSchedule,
        control: SimulationControl?,
        telemetry: WorldStepTelemetry?,
        chainFactory: @escaping () throws -> MotorNerveChain
    ) async throws -> KuyAtt1RunOutput {
        let runner = ReferenceQuadrotorScenarioRunner<ImuRateDampingDriveCut, MotorNerveChain>(
            parameters: parameters,
            schedule: schedule,
            determinism: request.determinism,
            noise: request.noise,
            environment: .standard,
            hoverThrustScale: request.gains.hoverThrustScale
        )

        let definitions = try referenceQuadrotorScenarioDefinitions(for: .lift)
        let manifest = ReferenceQuadrotorScenarioManifestBuilder().build(from: definitions)
        var evaluations: [ScenarioEvaluation] = []
        var logs: [ScenarioLogEntry] = []

        for definition in definitions {
            if let control {
                try await control.checkpoint()
            }
            let cut = try ImuRateDampingDriveCut(
                hoverThrust: parameters.mass * parameters.gravity / 4.0 * request.gains.hoverThrustScale,
                kp: request.gains.kp,
                kd: request.gains.kd,
                yawDamping: request.gains.yawDamping,
                armLength: parameters.armLength,
                yawCoefficient: parameters.yawCoefficient,
                maxThrust: parameters.maxThrust,
                initialRoll: definition.initialAttitude.roll,
                initialPitch: definition.initialAttitude.pitch,
                tiltCorrectionTimeConstant: nil
            )
            let log = try await runner.runScenario(
                definition: definition,
                cut: cut,
                motorNerve: try chainFactory(),
                control: control,
                telemetry: telemetry
            )
            let key = ScenarioKey(scenarioId: definition.config.id, seed: definition.config.seed)
            logs.append(ScenarioLogEntry(key: key, log: log))
            let evaluation = ReferenceQuadrotorScenarioEvaluator().evaluate(definition: definition, log: log)
            evaluations.append(evaluation)
        }

        let result = SuiteRunResultFactory().makeEvaluationOnly(
            evaluations: evaluations,
            replaySkippedReason: "Interactive simulation runs do not execute replay verification."
        )
        let aggregate = EvaluationAggregate.from(evaluations: result.evaluations)
        let summary = ValidationSummary(
            suitePassed: result.passed,
            evaluations: result.evaluations,
            replay: result.replay,
            manifest: manifest,
            aggregate: aggregate
        )

        return KuyAtt1RunOutput(result: result, summary: summary, logs: logs)
    }

    private func runSingleLiftBaseline(
        request: SimulationRunRequest,
        parameters: ReferenceQuadrotorParameters,
        schedule: SimulationSchedule,
        control: SimulationControl?,
        telemetry: WorldStepTelemetry?
    ) async throws -> KuyAtt1RunOutput {
        let runner = ReferenceQuadrotorScenarioRunner<SinglePropHoverCut, FixedSinglePropMotorNerve>(
            parameters: parameters,
            schedule: schedule,
            determinism: request.determinism,
            noise: request.noise,
            environment: .standard,
            hoverThrustScale: request.gains.hoverThrustScale
        )

        let definitions = try referenceQuadrotorScenarioDefinitions(for: .singleLift)
        let manifest = ReferenceQuadrotorScenarioManifestBuilder().build(from: definitions)
        var evaluations: [ScenarioEvaluation] = []
        var logs: [ScenarioLogEntry] = []

        for definition in definitions {
            if let control {
                try await control.checkpoint()
            }
            let hoverThrust = parameters.mass * parameters.gravity * request.gains.hoverThrustScale
            let baseThrottle = 0.0
            let targetZ = definition.liftEnvelope?.targetZ ?? 0.5
            let baselineMetadata: Logger.Metadata = [
                "action": "activeAltitudeHold",
                "task": .string(request.taskMode.rawValue),
                "hoverThrustScale": .string(String(format: "%.3f", request.gains.hoverThrustScale)),
                "hoverThrust": .string(String(format: "%.3f", hoverThrust)),
                "maxThrust": .string(String(format: "%.3f", parameters.maxThrust)),
                "baseThrottle": .string(String(format: "%.3f", baseThrottle)),
                "targetZ": .string(String(format: "%.3f", targetZ))
            ]
            logger.info("Single Lift baseline config", metadata: baselineMetadata)
            let cut = try SinglePropHoverCut(
                targetZ: targetZ,
                hoverThrust: hoverThrust,
                maxThrust: parameters.maxThrust
            )
            let motorNerveConfig = FixedSinglePropMotorNerve.Config(
                maxThrust: parameters.maxThrust,
                rateLimitPerSecond: 100.0,
                smoothingTimeConstant: nil,
                baseThrottle: baseThrottle
            )
            let log = try await runner.runScenario(
                definition: definition,
                cut: cut,
                motorNerve: FixedSinglePropMotorNerve(config: motorNerveConfig),
                control: control,
                telemetry: telemetry
            )
            let key = ScenarioKey(scenarioId: definition.config.id, seed: definition.config.seed)
            logs.append(ScenarioLogEntry(key: key, log: log))
            let evaluation = ReferenceQuadrotorScenarioEvaluator().evaluate(definition: definition, log: log)
            evaluations.append(evaluation)
        }

        let result = SuiteRunResultFactory().makeEvaluationOnly(
            evaluations: evaluations,
            replaySkippedReason: "Interactive simulation runs do not execute replay verification."
        )
        let aggregate = EvaluationAggregate.from(evaluations: result.evaluations)
        let summary = ValidationSummary(
            suitePassed: result.passed,
            evaluations: result.evaluations,
            replay: result.replay,
            manifest: manifest,
            aggregate: aggregate
        )

        return KuyAtt1RunOutput(result: result, summary: summary, logs: logs)
    }

    private func runSingleLiftBaselineWithChain(
        request: SimulationRunRequest,
        parameters: ReferenceQuadrotorParameters,
        schedule: SimulationSchedule,
        control: SimulationControl?,
        telemetry: WorldStepTelemetry?,
        chainFactory: @escaping () throws -> MotorNerveChain
    ) async throws -> KuyAtt1RunOutput {
        let runner = ReferenceQuadrotorScenarioRunner<SinglePropHoverCut, MotorNerveChain>(
            parameters: parameters,
            schedule: schedule,
            determinism: request.determinism,
            noise: request.noise,
            environment: .standard,
            hoverThrustScale: request.gains.hoverThrustScale
        )

        let definitions = try referenceQuadrotorScenarioDefinitions(for: .singleLift)
        let manifest = ReferenceQuadrotorScenarioManifestBuilder().build(from: definitions)
        var evaluations: [ScenarioEvaluation] = []
        var logs: [ScenarioLogEntry] = []

        for definition in definitions {
            if let control {
                try await control.checkpoint()
            }
            let hoverThrust = parameters.mass * parameters.gravity * request.gains.hoverThrustScale
            let baseThrottle = 0.0
            let targetZ = definition.liftEnvelope?.targetZ ?? 0.5
            let baselineMetadata: Logger.Metadata = [
                "action": "activeAltitudeHold",
                "task": .string(request.taskMode.rawValue),
                "hoverThrustScale": .string(String(format: "%.3f", request.gains.hoverThrustScale)),
                "hoverThrust": .string(String(format: "%.3f", hoverThrust)),
                "maxThrust": .string(String(format: "%.3f", parameters.maxThrust)),
                "baseThrottle": .string(String(format: "%.3f", baseThrottle)),
                "targetZ": .string(String(format: "%.3f", targetZ))
            ]
            logger.info("Single Lift baseline config", metadata: baselineMetadata)
            let cut = try SinglePropHoverCut(
                targetZ: targetZ,
                hoverThrust: hoverThrust,
                maxThrust: parameters.maxThrust
            )
            let log = try await runner.runScenario(
                definition: definition,
                cut: cut,
                motorNerve: try chainFactory(),
                control: control,
                telemetry: telemetry
            )
            let key = ScenarioKey(scenarioId: definition.config.id, seed: definition.config.seed)
            logs.append(ScenarioLogEntry(key: key, log: log))
            let evaluation = ReferenceQuadrotorScenarioEvaluator().evaluate(definition: definition, log: log)
            evaluations.append(evaluation)
        }

        let result = SuiteRunResultFactory().makeEvaluationOnly(
            evaluations: evaluations,
            replaySkippedReason: "Interactive simulation runs do not execute replay verification."
        )
        let aggregate = EvaluationAggregate.from(evaluations: result.evaluations)
        let summary = ValidationSummary(
            suitePassed: result.passed,
            evaluations: result.evaluations,
            replay: result.replay,
            manifest: manifest,
            aggregate: aggregate
        )

        return KuyAtt1RunOutput(result: result, summary: summary, logs: logs)
    }

}

public enum SimulationRunnerServiceError: Error, Equatable {
    case robotManifestParametersUnavailable(String)
    case motorNerveDriveCountMismatch(modelPath: String, expected: Int, actual: Int)
    case unsupportedMotorNerveStage(modelPath: String, stageID: String)
}

public struct SimulationParameterResolution: Sendable, Equatable {
    public enum Source: String, Sendable, Codable, Equatable {
        case referenceBaseline
        case robotManifest
        case override
    }

    public let parameters: ReferenceQuadrotorParameters
    public let embodiment: EmbodimentContract?
    public let source: Source
    public let robotID: String?

    public init(
        parameters: ReferenceQuadrotorParameters,
        embodiment: EmbodimentContract?,
        source: Source,
        robotID: String?
    ) {
        self.parameters = parameters
        self.embodiment = embodiment
        self.source = source
        self.robotID = robotID
    }

    public init(_ resolution: ReferenceQuadrotorParameterResolution) {
        self.init(
            parameters: resolution.parameters,
            embodiment: resolution.embodiment,
            source: Source(resolution.source),
            robotID: resolution.robotID
        )
    }
}

private extension SimulationParameterResolution.Source {
    init(_ source: ReferenceQuadrotorParameterResolutionSource) {
        switch source {
        case .referenceBaseline:
            self = .referenceBaseline
        case .robotManifest:
            self = .robotManifest
        case .override:
            self = .override
        }
    }
}
