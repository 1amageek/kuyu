import KuyuCore
import KuyuMLX
import Logging
import KuyuPhysics
import KuyuScenarios

public struct SimulationRunnerService: @unchecked Sendable {
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
        let schedule = try SimulationSchedule.baseline(cutPeriodSteps: request.cutPeriodSteps)
        let resolution = try resolveParameters(request: request)
        let parameters = resolution.parameters
        let descriptor = resolution.descriptor
        switch request.controller {
        case .baseline, .teacherBaseline, .sensorBaseline:
            let baselineMode = request.controller.kuyAtt1BaselineMode ?? .teacher
            if let store = manualActuatorStore, store.isEnabled, request.taskMode != .singleLift {
                return try await runManualBaseline(
                    request: request,
                    parameters: parameters,
                    descriptor: descriptor,
                    schedule: schedule,
                    control: control,
                    telemetry: telemetry,
                    store: store
                )
            }
            if request.taskMode == .lift {
                if let chainFactory = motorNerveChainFactory(
                    descriptor: descriptor,
                    request: request,
                    expectedDriveCount: 4,
                    fallbackProfile: "lift"
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
                if let chainFactory = motorNerveChainFactory(
                    descriptor: descriptor,
                    request: request,
                    expectedDriveCount: 1,
                    fallbackProfile: "fixed-single-prop"
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
            if let chainFactory = motorNerveChainFactory(
                descriptor: descriptor,
                request: request,
                expectedDriveCount: 4,
                fallbackProfile: "fixed-quad"
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
            let runner = KuyAtt1Runner(
                parameters: parameters,
                schedule: schedule,
                determinism: request.determinism,
                noise: request.noise,
                gains: request.gains,
                baselineMode: baselineMode
            )
            return try await runner.runWithLogs(control: control)
        case .manasMLX:
            try MLXRuntimePreflight().check()
            return try await modelStore.runManasMLX(
                parameters: parameters,
                schedule: schedule,
                request: request,
                descriptor: descriptor,
                control: control,
                telemetry: telemetry
            )
        }
    }

    private func loadDescriptor(path: String, task: SimulationTaskMode) throws -> LoadedRobotDescriptor? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        do {
            let loader = RobotDescriptorLoader()
            return try loader.loadDescriptor(path: trimmed)
        } catch {
            logger.error("RobotDescriptor load failed", metadata: [
                "action": "descriptorLoadFailed",
                "task": .string(task.rawValue),
                "model": .string(trimmed),
                "modelDescriptor": .string(trimmed),
                "reason": "loadFailed",
                "error": .string(String(describing: error))
            ])
            throw error
        }
    }

    private func resolveParameters(request: SimulationRunRequest) throws -> SimulationParameterResolution {
        let loadedDescriptor = try loadDescriptor(path: request.modelDescriptorPath, task: request.taskMode)
        return try loadParameters(request: request, loadedDescriptor: loadedDescriptor)
    }

    private func motorNerveChainFactory(
        descriptor: RobotDescriptor?,
        request: SimulationRunRequest,
        expectedDriveCount: Int,
        fallbackProfile: String
    ) -> (() throws -> MotorNerveChain)? {
        guard let descriptor else { return nil }
        let modelPath = request.modelDescriptorPath.trimmingCharacters(in: .whitespacesAndNewlines)

        if descriptor.control.driveChannels.count != expectedDriveCount {
            logger.warning("MotorNerveChain disabled due to drive count mismatch", metadata: [
                "action": "motorNerveFallback",
                "task": .string(request.taskMode.rawValue),
                "model": .string(modelPath),
                "from": "descriptor-chain",
                "to": .string(fallbackProfile),
                "reason": "driveCountMismatch",
                "motorNerveProfile": .string(fallbackProfile)
            ])
            return nil
        }

        if descriptor.motorNerve.stages.contains(where: { $0.type == .custom }) {
            logger.warning("MotorNerveChain disabled due to unsupported stage", metadata: [
                "action": "motorNerveFallback",
                "task": .string(request.taskMode.rawValue),
                "model": .string(modelPath),
                "from": "descriptor-chain",
                "to": .string(fallbackProfile),
                "reason": "unsupportedCustomStage",
                "motorNerveProfile": .string(fallbackProfile)
            ])
            return nil
        }

        logger.notice("MotorNerveChain enabled", metadata: [
            "action": "motorNerveChain",
            "task": .string(request.taskMode.rawValue),
            "model": .string(modelPath),
            "motorNerveProfile": "descriptor-chain"
        ])

        return { try MotorNerveChain(descriptor: descriptor) }
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
            replayChecks: output.result.replayChecks,
            manifest: output.manifest,
            aggregate: aggregate
        )

        return KuyAtt1RunOutput(result: output.result, summary: summary, logs: output.logs)
    }

    private func loadParameters(
        request: SimulationRunRequest,
        loadedDescriptor: LoadedRobotDescriptor?
    ) throws -> SimulationParameterResolution {
        if let override = request.overrideParameters {
            return SimulationParameterResolution(
                parameters: override,
                descriptor: loadedDescriptor?.descriptor,
                source: .override,
                robotID: loadedDescriptor?.descriptor.robot.robotID
            )
        }

        guard let loadedDescriptor else {
            let modelPath = request.modelDescriptorPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !modelPath.isEmpty {
                logger.error("RobotDescriptor parameters unavailable", metadata: [
                    "action": "descriptorParametersFailed",
                    "task": .string(request.taskMode.rawValue),
                    "model": .string(modelPath),
                    "modelDescriptor": .string(modelPath),
                    "reason": "descriptorNotLoaded",
                    "error": "descriptorNotLoaded"
                ])
                throw SimulationRunnerServiceError.descriptorParametersUnavailable(modelPath)
            }
            return SimulationParameterResolution(
                parameters: try defaultParameters(for: request.taskMode, hoverThrustScale: request.gains.hoverThrustScale),
                descriptor: nil,
                source: .referenceBaseline,
                robotID: nil
            )
        }

        do {
            let loader = RobotDescriptorLoader()
            let inertial = try loader.loadPlantInertialProperties(descriptor: loadedDescriptor)
            let parameters = try ReferenceQuadrotorParameters.reference(
                from: inertial,
                robotID: loadedDescriptor.descriptor.robot.robotID
            )
            let tunedParameters = request.taskMode == .singleLift
                ? try KuyuSingleLiftParameterTuning.tuned(
                    parameters: parameters,
                    hoverThrustScale: request.gains.hoverThrustScale
                )
                : parameters
            return SimulationParameterResolution(
                parameters: tunedParameters,
                descriptor: loadedDescriptor.descriptor,
                source: .descriptor,
                robotID: loadedDescriptor.descriptor.robot.robotID
            )
        } catch {
            logger.error("RobotDescriptor inertial load failed", metadata: [
                "action": "descriptorParametersFailed",
                "task": .string(request.taskMode.rawValue),
                "model": .string(request.modelDescriptorPath),
                "modelDescriptor": .string(request.modelDescriptorPath),
                "reason": "inertialLoadFailed",
                "error": .string(String(describing: error))
            ])
            throw error
        }
    }

    private func runManualBaseline(
        request: SimulationRunRequest,
        parameters: ReferenceQuadrotorParameters,
        descriptor: RobotDescriptor?,
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

        let definitions: [ReferenceQuadrotorScenarioDefinition]
        switch request.taskMode {
        case .lift:
            definitions = try KuyLiftSuite().scenarios()
        case .attitude:
            definitions = try KuyAtt1Suite().scenarios()
        case .singleLift:
            definitions = try KuySingleLiftSuite().scenarios()
        }

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
                descriptor: descriptor,
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

        let result = SuiteRunResult(evaluations: evaluations, replayChecks: [], passed: evaluations.allSatisfy { $0.passed })
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

    private func manualActuatorChannelMaxima(
        descriptor: RobotDescriptor?,
        fallback: Double,
        expectedCount: Int
    ) -> [Double] {
        let safeFallback = max(fallback, 0.0)
        var maxima = Array(repeating: safeFallback, count: max(expectedCount, 1))

        guard let descriptor else { return maxima }

        let sortedSignals = descriptor.signals.actuator.sorted { $0.index < $1.index }
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
        for actuator in descriptor.actuators {
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

        let definitions = try KuyLiftSuite().scenarios()
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

        let result = SuiteRunResult(evaluations: evaluations, replayChecks: [], passed: evaluations.allSatisfy { $0.passed })
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

        let definitions = try KuyLiftSuite().scenarios()
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

        let result = SuiteRunResult(evaluations: evaluations, replayChecks: [], passed: evaluations.allSatisfy { $0.passed })
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

        let definitions = try KuySingleLiftSuite().scenarios()
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
                "action": "teacherBaseline",
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

        let result = SuiteRunResult(evaluations: evaluations, replayChecks: [], passed: evaluations.allSatisfy { $0.passed })
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

        let definitions = try KuySingleLiftSuite().scenarios()
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
                "action": "teacherBaseline",
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

        let result = SuiteRunResult(evaluations: evaluations, replayChecks: [], passed: evaluations.allSatisfy { $0.passed })
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

    private func defaultParameters(
        for taskMode: SimulationTaskMode,
        hoverThrustScale: Double
    ) throws -> ReferenceQuadrotorParameters {
        guard taskMode == .singleLift else {
            return .baseline
        }
        return try KuyuSingleLiftParameterTuning.tuned(
            parameters: .baseline,
            hoverThrustScale: hoverThrustScale
        )
    }
}

public enum SimulationRunnerServiceError: Error, Equatable {
    case descriptorParametersUnavailable(String)
}

public struct SimulationParameterResolution: Sendable, Equatable {
    public enum Source: String, Sendable, Codable, Equatable {
        case referenceBaseline
        case descriptor
        case override
    }

    public let parameters: ReferenceQuadrotorParameters
    public let descriptor: RobotDescriptor?
    public let source: Source
    public let robotID: String?

    public init(
        parameters: ReferenceQuadrotorParameters,
        descriptor: RobotDescriptor?,
        source: Source,
        robotID: String?
    ) {
        self.parameters = parameters
        self.descriptor = descriptor
        self.source = source
        self.robotID = robotID
    }
}
