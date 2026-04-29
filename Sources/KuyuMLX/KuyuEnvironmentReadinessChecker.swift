import Foundation
import KuyuCore
import KuyuPhysics
import KuyuScenarios
import KuyuTraining

public enum KuyuEnvironmentReadinessError: Error, Equatable {
    case unsupportedController(String)
}

@MainActor
public struct KuyuEnvironmentReadinessChecker {
    private let runtime: KuyuScenarioRuntime
    private let fileManager: FileManager

    public init(
        runtime: KuyuScenarioRuntime = KuyuScenarioRuntime(modelStore: ManasMLXModelStore()),
        fileManager: FileManager = .default
    ) {
        self.runtime = runtime
        self.fileManager = fileManager
    }

    public func check(
        tasks: [SimulationTaskMode],
        controller: ControllerSelection = .teacherBaseline,
        parameters: ReferenceQuadrotorParameters,
        schedule: SimulationSchedule,
        determinism: DeterminismConfig,
        gains: ImuRateDampingCutGains,
        modelDescriptorPath: String = "",
        descriptor: RobotDescriptor? = nil,
        artifactRoot: URL? = nil
    ) async throws -> KuyuEnvironmentReadinessReport {
        guard controller.isBaselineController else {
            throw KuyuEnvironmentReadinessError.unsupportedController(controller.rawValue)
        }

        if let artifactRoot {
            try fileManager.createDirectory(at: artifactRoot, withIntermediateDirectories: true)
        }

        var results: [KuyuEnvironmentTaskReadiness] = []
        for task in tasks {
            let request = SimulationRunRequest(
                controller: controller,
                taskMode: task,
                gains: gains,
                cutPeriodSteps: schedule.cut.periodSteps,
                noise: .zero,
                determinism: determinism,
                modelDescriptorPath: modelDescriptorPath,
                overrideParameters: parameters,
                useAux: true,
                useQualityGating: true
            )
            let output = try await runtime.run(
                request: request,
                parameters: parameters,
                schedule: schedule,
                descriptor: descriptor
            )
            let taskArtifactRoot = artifactRoot?.appendingPathComponent(Self.taskID(for: task), isDirectory: true)
            let datasetScenarioCount = try writeArtifactsIfNeeded(
                output: output,
                taskArtifactRoot: taskArtifactRoot
            )
            results.append(Self.summarize(
                task: task,
                controller: controller,
                output: output,
                datasetScenarioCount: datasetScenarioCount,
                artifactRoot: taskArtifactRoot
            ))
        }

        let report = KuyuEnvironmentReadinessReport(tasks: results)
        if let artifactRoot {
            try Self.write(report: report, to: artifactRoot)
        }
        return report
    }

    public nonisolated static func summarize(
        task: SimulationTaskMode,
        controller: ControllerSelection,
        output: KuyAtt1RunOutput,
        datasetScenarioCount: Int,
        artifactRoot: URL?
    ) -> KuyuEnvironmentTaskReadiness {
        let scenarioCount = output.summary.manifest.count
        let logCount = output.logs.count
        let failureReasons = output.summary.evaluations.flatMap { evaluation in
            evaluation.failures
        }
        let failureCount = output.summary.evaluations.filter { !$0.passed }.count
        let safetyViolationSeconds = output.summary.evaluations.reduce(0.0) { partial, evaluation in
            partial + evaluation.sustainedViolationSeconds
        }
        let logsWithActions = output.logs.filter { entry in
            entry.log.events.contains { hasAction($0) }
        }.count
        let allEvents = output.logs.flatMap(\.log.events)
        let eventsWithActions = allEvents.filter { hasAction($0) }.count
        let scenarioActionCoverage = ratio(logsWithActions, logCount)
        let stepActionCoverage = ratio(eventsWithActions, allEvents.count)
        let score = score(from: output.summary)

        var readinessFailures: [String] = []
        if !output.summary.suitePassed {
            readinessFailures.append("suite did not pass")
        }
        if !score.isFinite {
            readinessFailures.append("score is not finite")
        }
        if scenarioCount == 0 {
            readinessFailures.append("scenario manifest is empty")
        }
        if logCount != scenarioCount {
            readinessFailures.append("log count does not match scenario count")
        }
        if datasetScenarioCount != scenarioCount {
            readinessFailures.append("dataset scenario count does not match scenario count")
        }
        if scenarioActionCoverage < 1.0 {
            readinessFailures.append("one or more scenarios have no teacher action labels")
        }
        if safetyViolationSeconds > 0 {
            readinessFailures.append("safety violation seconds are non-zero")
        }

        let combinedFailures = Array(Set(failureReasons + readinessFailures)).sorted()
        let ready = combinedFailures.isEmpty

        return KuyuEnvironmentTaskReadiness(
            task: Self.taskID(for: task),
            controller: controller.rawValue,
            ready: ready,
            suitePassed: output.summary.suitePassed,
            score: score,
            scenarioCount: scenarioCount,
            logCount: logCount,
            datasetScenarioCount: datasetScenarioCount,
            failureCount: failureCount,
            safetyViolationSeconds: safetyViolationSeconds,
            scenarioActionCoverage: scenarioActionCoverage,
            stepActionCoverage: stepActionCoverage,
            artifactPath: artifactRoot?.path,
            failureReasons: combinedFailures
        )
    }

    public nonisolated static func taskID(for task: SimulationTaskMode) -> String {
        switch task {
        case .attitude:
            return "attitude"
        case .lift:
            return "lift"
        case .singleLift:
            return "singleLift"
        }
    }

    public nonisolated static func write(
        report: KuyuEnvironmentReadinessReport,
        to artifactRoot: URL
    ) throws {
        try FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(report).write(
            to: artifactRoot.appendingPathComponent("environment-readiness.json"),
            options: [.atomic]
        )
    }

    private func writeArtifactsIfNeeded(
        output: KuyAtt1RunOutput,
        taskArtifactRoot: URL?
    ) throws -> Int {
        guard let taskArtifactRoot else {
            return output.logs.count
        }

        try fileManager.createDirectory(at: taskArtifactRoot, withIntermediateDirectories: true)
        let logsRoot = taskArtifactRoot.appendingPathComponent("logs", isDirectory: true)
        _ = try KuyAtt1LogWriter().write(output: output, to: logsRoot)
        let datasetRoot = taskArtifactRoot.appendingPathComponent("dataset", isDirectory: true)
        let datasets = try TrainingDatasetExporter().write(output: output, to: datasetRoot)
        return datasets.count
    }

    private nonisolated static func hasAction(_ step: WorldStepLog) -> Bool {
        !step.driveIntents.isEmpty || !step.actuatorValues.isEmpty
    }

    private nonisolated static func ratio(_ numerator: Int, _ denominator: Int) -> Double {
        guard denominator > 0 else { return 0 }
        return Double(numerator) / Double(denominator)
    }

    private nonisolated static func score(from summary: ValidationSummary) -> Double {
        var score = summary.suitePassed ? 1.0 : 0.0
        if let worstOvershoot = summary.aggregate.worstOvershootDegrees {
            score -= min(1.0, worstOvershoot / 90.0) * 0.4
        }
        if let recovery = summary.aggregate.averageRecoveryTime {
            score -= min(1.0, recovery / 5.0) * 0.3
        }
        if let hf = summary.aggregate.averageHfStabilityScore {
            score += max(0.0, min(hf, 1.0)) * 0.2
        }
        return score
    }
}
