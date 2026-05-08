import Foundation
import KuyuTraining

public protocol LearningCampaignEvolutionRunning: Sendable {
    func runEvolution(
        seed: String,
        parentCheckpointURL: URL,
        artifactRoot: URL,
        plan: LearningCampaignPlan
    ) async throws -> EvolutionRunArtifactBundle
}

public extension LearningCampaignEvolutionRunning {
    func runEvolution(
        seed: String,
        parentCheckpointURL: URL,
        artifactRoot: URL,
        plan: LearningCampaignPlan,
        onEvent: (@Sendable (EvolutionRunEvent) -> Void)?
    ) async throws -> EvolutionRunArtifactBundle {
        _ = onEvent
        return try await runEvolution(
            seed: seed,
            parentCheckpointURL: parentCheckpointURL,
            artifactRoot: artifactRoot,
            plan: plan
        )
    }
}

public protocol LearningCampaignCheckpointRegressionChecking: Sendable {
    func checkCheckpointRegression(
        label: String,
        checkpointURL: URL,
        artifactRoot: URL,
        plan: LearningCampaignPlan
    ) async throws -> KuyuRegressionSummary
}

public struct LearningCampaignOrchestratorConfig: Sendable, Equatable {
    public let plan: LearningCampaignPlan
    public let artifactRoot: URL
    public let initialParentCheckpointURL: URL
    public let allowsNonEmptyArtifactRoot: Bool

    public init(
        plan: LearningCampaignPlan,
        artifactRoot: URL,
        initialParentCheckpointURL: URL,
        allowsNonEmptyArtifactRoot: Bool = false
    ) {
        self.plan = plan
        self.artifactRoot = artifactRoot
        self.initialParentCheckpointURL = initialParentCheckpointURL
        self.allowsNonEmptyArtifactRoot = allowsNonEmptyArtifactRoot
    }
}

public enum LearningCampaignOrchestratorError: Error, Sendable, Equatable {
    case artifactRootNotEmpty(path: String)
    case parentCheckpointEvaluationRejected(label: String, checkpointPath: String)
    case parentCheckpointRegressionRejected(label: String, checkpointPath: String, reasons: [String])
    case validationRejected([LearningCampaignValidationIssue])
}

@MainActor
public struct LearningCampaignOrchestrator: Sendable {
    private let checkpointEvaluator: any CheckpointEvaluating
    private let evolutionRunner: any LearningCampaignEvolutionRunning
    private let checkpointRegressionChecker: (any LearningCampaignCheckpointRegressionChecking)?
    private let validator: LearningCampaignArtifactValidator
    private let artifactPruner: LearningCampaignArtifactPruner

    public init(
        checkpointEvaluator: any CheckpointEvaluating,
        evolutionRunner: any LearningCampaignEvolutionRunning,
        checkpointRegressionChecker: (any LearningCampaignCheckpointRegressionChecking)? = nil,
        validator: LearningCampaignArtifactValidator = LearningCampaignArtifactValidator(),
        artifactPruner: LearningCampaignArtifactPruner = LearningCampaignArtifactPruner()
    ) {
        self.checkpointEvaluator = checkpointEvaluator
        self.evolutionRunner = evolutionRunner
        self.checkpointRegressionChecker = checkpointRegressionChecker
        self.validator = validator
        self.artifactPruner = artifactPruner
    }

    public func run(
        config: LearningCampaignOrchestratorConfig,
        context: LearningCampaignRunContext? = nil
    ) async throws -> LearningCampaignSummary {
        let startedAt = Date()
        var currentParentCheckpointURL = config.initialParentCheckpointURL
        var runs: [LearningCampaignSeedRunSummary] = []
        var retentionRecords: [LearningCampaignArtifactRetentionRecord] = []

        try rejectNonEmptyArtifactRootIfNeeded(config)
        do {
            try context?.checkCancellation()
            try FileManager.default.createDirectory(at: config.artifactRoot, withIntermediateDirectories: true)
            try write(config.plan, fileName: "learning-campaign-plan.json", root: config.artifactRoot)
            context?.emit(.artifactWritten(
                name: "learning-campaign-plan.json",
                path: config.artifactRoot.appendingPathComponent("learning-campaign-plan.json").path
            ))
            try writeEnvironment(root: config.artifactRoot)
            try writeResourceSampleIfNeeded(plan: config.plan, root: config.artifactRoot)
            try appendProgress(event: "campaign-started", root: config.artifactRoot)
            context?.advanceProgress(description: "Campaign started")

            let profile = try TaskEvaluationProfile.profile(task: config.plan.task)
            if config.plan.verifyParentTask != false {
                try await evaluateCheckpoint(
                    label: "initial-parent",
                    checkpointURL: currentParentCheckpointURL,
                    profile: profile,
                    root: config.artifactRoot,
                    requiresPolicyPass: true,
                    context: context
                )
                try await evaluateCheckpointRegression(
                    label: "initial-parent",
                    checkpointURL: currentParentCheckpointURL,
                    root: config.artifactRoot,
                    plan: config.plan,
                    context: context
                )
            }

            for seed in config.plan.seeds {
                try context?.checkCancellation()
                context?.emit(.seedStarted(seed: seed))
                let evolutionRoot = config.artifactRoot
                    .appendingPathComponent("seeds", isDirectory: true)
                    .appendingPathComponent("seed-\(seed)", isDirectory: true)
                    .appendingPathComponent("evolution", isDirectory: true)
                let bundle: EvolutionRunArtifactBundle
                if let context {
                    let eventBox = EvolutionEventContinuationBox()
                    let stream = AsyncStream<EvolutionRunEvent> { streamContinuation in
                        eventBox.set(streamContinuation)
                    }
                    let eventTask = Task { @MainActor in
                        for await event in stream {
                            forwardEvolutionEvent(event, seed: seed, context: context)
                        }
                    }
                    do {
                        bundle = try await evolutionRunner.runEvolution(
                            seed: seed,
                            parentCheckpointURL: currentParentCheckpointURL,
                            artifactRoot: evolutionRoot,
                            plan: config.plan,
                            onEvent: { event in
                                eventBox.yield(event)
                            }
                        )
                        eventBox.finish()
                        await eventTask.value
                    } catch {
                        eventBox.finish()
                        await eventTask.value
                        throw error
                    }
                } else {
                    bundle = try await evolutionRunner.runEvolution(
                        seed: seed,
                        parentCheckpointURL: currentParentCheckpointURL,
                        artifactRoot: evolutionRoot,
                        plan: config.plan
                    )
                }
                let runSummary = makeSeedRunSummary(seed: seed, bundle: bundle)
                runs.append(runSummary)
                context?.emit(.seedCompleted(
                    seed: seed,
                    accepted: runSummary.accepted,
                    bestCandidateID: runSummary.bestCandidateID
                ))
                context?.advanceProgress(description: "Seed \(seed) completed")

                if bundle.acceptedCheckpoint.accepted,
                   let acceptedCheckpointURL = bundle.acceptedCheckpoint.checkpointURL {
                    try await evaluateCheckpoint(
                        label: "seed-\(seed)-accepted",
                        checkpointURL: acceptedCheckpointURL,
                        profile: profile,
                        root: config.artifactRoot,
                        requiresPolicyPass: true,
                        context: context
                    )
                    try await evaluateCheckpointRegression(
                        label: "seed-\(seed)-accepted",
                        checkpointURL: acceptedCheckpointURL,
                        root: config.artifactRoot,
                        plan: config.plan,
                        context: context
                    )
                    currentParentCheckpointURL = acceptedCheckpointURL
                }
                let retentionRecord = try artifactPruner.pruneSeedArtifacts(
                    seed: seed,
                    evolutionRoot: evolutionRoot,
                    bundle: bundle,
                    policy: config.plan.artifactRetentionPolicy
                )
                retentionRecords.append(retentionRecord)
            }
            let retentionSummary = LearningCampaignArtifactRetentionSummary(
                mode: config.plan.artifactRetentionPolicy.mode,
                records: retentionRecords
            )
            try write(retentionSummary, fileName: "artifact-retention.json", root: config.artifactRoot)
            context?.emit(.artifactWritten(
                name: "artifact-retention.json",
                path: config.artifactRoot.appendingPathComponent("artifact-retention.json").path
            ))

            let summary = LearningCampaignSummary(
                artifactRoot: config.artifactRoot.path,
                seedCount: config.plan.seeds.count,
                acceptedCount: runs.filter(\.accepted).count,
                finalCheckpoint: currentParentCheckpointURL.path,
                runs: runs,
                retention: retentionSummary
            )
            try write(summary, fileName: "learning-campaign-summary.json", root: config.artifactRoot)
            context?.emit(.artifactWritten(
                name: "learning-campaign-summary.json",
                path: config.artifactRoot.appendingPathComponent("learning-campaign-summary.json").path
            ))
            try appendProgress(event: "summary-written", root: config.artifactRoot)
            try writeStatus(status: "succeeded", exitCode: 0, startedAt: startedAt, root: config.artifactRoot)
            try writeFinishedProgress(status: "succeeded", exitCode: 0, root: config.artifactRoot)
            do {
                _ = try validator.validate(artifactRoot: config.artifactRoot)
            } catch LearningCampaignArtifactValidator.ValidationError.invalid(let validation) {
                try writeStatus(status: "failed", exitCode: 1, startedAt: startedAt, root: config.artifactRoot)
                try writeFinishedProgress(status: "failed", exitCode: 1, root: config.artifactRoot)
                try regenerateFailedValidationArtifact(root: config.artifactRoot)
                context?.emit(.failed(reason: "validation-rejected"))
                throw LearningCampaignOrchestratorError.validationRejected(validation.issues)
            }
            context?.finishProgress(description: "Campaign completed")
            context?.emit(.finished(summary: summary))
            return summary
        } catch is CancellationError {
            try writeStatus(status: "cancelled", exitCode: 130, startedAt: startedAt, root: config.artifactRoot)
            try writeFinishedProgress(status: "cancelled", exitCode: 130, root: config.artifactRoot)
            try regenerateFailedValidationArtifact(root: config.artifactRoot)
            context?.emit(.cancelled)
            throw CancellationError()
        } catch let error as LearningCampaignOrchestratorError {
            if case .validationRejected = error {
                throw error
            }
            try writeStatus(status: "failed", exitCode: 1, startedAt: startedAt, root: config.artifactRoot)
            try writeFinishedProgress(status: "failed", exitCode: 1, root: config.artifactRoot)
            try regenerateFailedValidationArtifact(root: config.artifactRoot)
            context?.emit(.failed(reason: String(describing: error)))
            throw error
        } catch {
            try writeStatus(status: "failed", exitCode: 1, startedAt: startedAt, root: config.artifactRoot)
            try writeFinishedProgress(status: "failed", exitCode: 1, root: config.artifactRoot)
            try regenerateFailedValidationArtifact(root: config.artifactRoot)
            context?.emit(.failed(reason: String(describing: error)))
            throw error
        }
    }

    private func rejectNonEmptyArtifactRootIfNeeded(_ config: LearningCampaignOrchestratorConfig) throws {
        guard !config.allowsNonEmptyArtifactRoot else { return }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: config.artifactRoot.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return
        }
        let contents = try FileManager.default.contentsOfDirectory(
            at: config.artifactRoot,
            includingPropertiesForKeys: nil,
            options: []
        )
        guard contents.isEmpty else {
            throw LearningCampaignOrchestratorError.artifactRootNotEmpty(path: config.artifactRoot.path)
        }
    }

    private func evaluateCheckpoint(
        label: String,
        checkpointURL: URL,
        profile: TaskEvaluationProfile,
        root: URL,
        requiresPolicyPass: Bool,
        context: LearningCampaignRunContext?
    ) async throws {
        try context?.checkCancellation()
        context?.emit(.parentEvaluationStarted(label: label, checkpointPath: checkpointURL.path))
        let artifactRoot = root
            .appendingPathComponent("checkpoint-evaluations", isDirectory: true)
            .appendingPathComponent(label, isDirectory: true)
        let artifact = try await checkpointEvaluator.evaluateCheckpoint(
            request: CheckpointEvaluationRequest(
                evaluationID: "campaign-\(label)",
                profile: profile,
                checkpointURL: checkpointURL,
                artifactRoot: artifactRoot
            )
        )
        do {
            try CheckpointEvaluationArtifactValidator.validate(
                artifact,
                expectedProfile: profile,
                expectedCheckpointPath: checkpointURL.path,
                requiresPolicyPass: requiresPolicyPass
            )
        } catch {
            throw LearningCampaignOrchestratorError.parentCheckpointEvaluationRejected(
                label: label,
                checkpointPath: checkpointURL.path
            )
        }
        context?.emit(.parentEvaluationCompleted(label: label, checkpointPath: checkpointURL.path))
        context?.advanceProgress(description: "\(label) checkpoint evaluated")
    }

    private func forwardEvolutionEvent(
        _ event: EvolutionRunEvent,
        seed: String,
        context: LearningCampaignRunContext
    ) {
        switch event {
        case .generationStarted(let generationIndex):
            context.emit(.generationStarted(seed: seed, generationIndex: generationIndex))
        case .candidateEvaluated(let fitness):
            context.emit(.candidateEvaluated(
                seed: seed,
                generationIndex: fitness.generationIndex,
                candidateID: fitness.candidateID,
                fitness: fitness.scalarFitness
            ))
        case .generationCompleted(let record):
            context.emit(.generationCompleted(
                seed: seed,
                generationIndex: record.generationIndex,
                bestCandidateID: record.bestCandidateID
            ))
            context.advanceProgress(description: "Seed \(seed) generation \(record.generationIndex) completed")
        default:
            break
        }
    }

    private func evaluateCheckpointRegression(
        label: String,
        checkpointURL: URL,
        root: URL,
        plan: LearningCampaignPlan,
        context: LearningCampaignRunContext?
    ) async throws {
        guard let checkpointRegressionChecker else { return }
        try context?.checkCancellation()
        context?.emit(.checkpointRegressionStarted(label: label, checkpointPath: checkpointURL.path))
        let artifactRoot = root
            .appendingPathComponent("checkpoint-regressions", isDirectory: true)
            .appendingPathComponent(label, isDirectory: true)
        let summary = try await checkpointRegressionChecker.checkCheckpointRegression(
            label: label,
            checkpointURL: checkpointURL,
            artifactRoot: artifactRoot,
            plan: plan
        )
        try KuyuRegressionArtifactValidator().validate(summary)
        context?.emit(.checkpointRegressionCompleted(
            label: label,
            accepted: summary.allPassed,
            reasons: summary.gateReport.reasons
        ))
        context?.advanceProgress(description: "\(label) regression checked")
        guard summary.allPassed else {
            throw LearningCampaignOrchestratorError.parentCheckpointRegressionRejected(
                label: label,
                checkpointPath: checkpointURL.path,
                reasons: summary.gateReport.reasons
            )
        }
    }

    private func makeSeedRunSummary(
        seed: String,
        bundle: EvolutionRunArtifactBundle
    ) -> LearningCampaignSeedRunSummary {
        let best = bestFitness(in: bundle)
        let gateNearest = gateNearestFitness(in: bundle)
        let incumbentCandidateID = bundle.candidates.first { $0.isIncumbent == true }?.candidateID
        let incumbent = incumbentCandidateID.flatMap { candidateID in
            bundle.fitness.first { $0.candidateID == candidateID }
        }
        let bestVsIncumbentDelta: Double?
        if let bestFitness = best?.scalarFitness, let incumbentFitness = incumbent?.scalarFitness {
            bestVsIncumbentDelta = bestFitness - incumbentFitness
        } else {
            bestVsIncumbentDelta = nil
        }

        return LearningCampaignSeedRunSummary(
            seed: seed,
            terminalState: bundle.manifest.terminalState.rawValue,
            accepted: bundle.acceptedCheckpoint.accepted,
            acceptedCandidateID: bundle.acceptedCheckpoint.candidateID,
            acceptedCheckpointURL: bundle.acceptedCheckpoint.checkpointURL?.path,
            incumbentCandidateID: incumbentCandidateID,
            incumbentFitness: incumbent?.scalarFitness,
            bestCandidateID: best?.candidateID,
            bestFitness: best?.scalarFitness,
            bestVsIncumbentDelta: bestVsIncumbentDelta,
            bestTaskPassRate: best?.taskPassRate,
            bestHoldTimeRatio: best?.holdTimeRatio,
            bestAltitudeErrorRatio: best?.altitudeErrorRatio,
            bestSafetyViolationRate: best?.safetyViolationRate,
            bestRewardAverage: best?.rewardAverage,
            gateNearestCandidateID: gateNearest?.candidateID,
            gateNearestFitness: gateNearest?.scalarFitness,
            gateNearestTaskPassRate: gateNearest?.taskPassRate,
            gateNearestHoldTimeRatio: gateNearest?.holdTimeRatio,
            gateNearestAltitudeErrorRatio: gateNearest?.altitudeErrorRatio,
            gateNearestSafetyViolationRate: gateNearest?.safetyViolationRate,
            gateNearestRewardAverage: gateNearest?.rewardAverage,
            fitnessCount: bundle.fitness.count,
            reasonCount: bundle.acceptedCheckpoint.reasons.count,
            evaluationTraceCount: bundle.evaluationTraces.count,
            overlappedEvaluation: bundle.evaluationTraces.contains { $0.activeEvaluationCountAtStart > 1 }
        )
    }

    private func bestFitness(in bundle: EvolutionRunArtifactBundle) -> FitnessSummary? {
        bundle.fitness.sorted { lhs, rhs in
            if lhs.scalarFitness != rhs.scalarFitness {
                return lhs.scalarFitness > rhs.scalarFitness
            }
            if lhs.generationIndex != rhs.generationIndex {
                return lhs.generationIndex > rhs.generationIndex
            }
            return lhs.candidateID < rhs.candidateID
        }.first
    }

    private func gateNearestFitness(in bundle: EvolutionRunArtifactBundle) -> FitnessSummary? {
        bundle.fitness.sorted { lhs, rhs in
            if lhs.taskPassRate != rhs.taskPassRate {
                return lhs.taskPassRate > rhs.taskPassRate
            }
            if (lhs.holdTimeRatio ?? 0) != (rhs.holdTimeRatio ?? 0) {
                return (lhs.holdTimeRatio ?? 0) > (rhs.holdTimeRatio ?? 0)
            }
            if (lhs.altitudeErrorRatio ?? .greatestFiniteMagnitude)
                != (rhs.altitudeErrorRatio ?? .greatestFiniteMagnitude) {
                return (lhs.altitudeErrorRatio ?? .greatestFiniteMagnitude)
                    < (rhs.altitudeErrorRatio ?? .greatestFiniteMagnitude)
            }
            if lhs.safetyViolationRate != rhs.safetyViolationRate {
                return lhs.safetyViolationRate < rhs.safetyViolationRate
            }
            if lhs.rewardAverage != rhs.rewardAverage {
                return lhs.rewardAverage > rhs.rewardAverage
            }
            if lhs.scalarFitness != rhs.scalarFitness {
                return lhs.scalarFitness > rhs.scalarFitness
            }
            if lhs.generationIndex != rhs.generationIndex {
                return lhs.generationIndex > rhs.generationIndex
            }
            return lhs.candidateID < rhs.candidateID
        }.first
    }

    private func write<T: Encodable>(_ value: T, fileName: String, root: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: root.appendingPathComponent(fileName), options: [.atomic])
    }

    private func appendProgress(
        event: String,
        status: String? = nil,
        exitCode: Int? = nil,
        root: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let record = LearningCampaignProgressEvent(
            event: event,
            timestamp: Date(),
            status: status,
            exitCode: exitCode
        )
        let data = try encoder.encode(record)
        let url = root.appendingPathComponent("progress.jsonl")
        var output = FileManager.default.fileExists(atPath: url.path)
            ? try Data(contentsOf: url)
            : Data()
        output.append(data)
        output.append(Data("\n".utf8))
        try output.write(to: url, options: [.atomic])
    }

    private func writeFinishedProgress(status: String, exitCode: Int, root: URL) throws {
        let url = root.appendingPathComponent("progress.jsonl")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let records: [LearningCampaignProgressEvent]
        if FileManager.default.fileExists(atPath: url.path) {
            let raw = try String(contentsOf: url, encoding: .utf8)
            records = try raw
                .split(separator: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map { line in
                    try decoder.decode(LearningCampaignProgressEvent.self, from: Data(line.utf8))
                }
                .filter { $0.event != "campaign-finished" }
        } else {
            records = []
        }
        var output = Data()
        for record in records {
            output.append(try encoder.encode(record))
            output.append(Data("\n".utf8))
        }
        let finalRecord = LearningCampaignProgressEvent(
            event: "campaign-finished",
            timestamp: Date(),
            status: status,
            exitCode: exitCode
        )
        output.append(try encoder.encode(finalRecord))
        output.append(Data("\n".utf8))
        try output.write(to: url, options: [.atomic])
    }

    private func regenerateFailedValidationArtifact(root: URL) throws {
        do {
            _ = try validator.validate(
                artifactRoot: root,
                allowFailed: true,
                writesValidationArtifact: true
            )
        } catch LearningCampaignArtifactValidator.ValidationError.invalid {
            return
        }
    }

    private func writeStatus(
        status: String,
        exitCode: Int,
        startedAt: Date,
        root: URL
    ) throws {
        let formatter = ISO8601DateFormatter()
        let campaignStatus = LearningCampaignStatus(
            status: status,
            exitCode: exitCode,
            startedAt: formatter.string(from: startedAt),
            finishedAt: formatter.string(from: Date())
        )
        try write(campaignStatus, fileName: "campaign-status.json", root: root)
    }

    private func writeEnvironment(root: URL) throws {
        let processEnvironment = ProcessInfo.processInfo.environment
        let repositoryPath = FileManager.default.currentDirectoryPath
        let environment = LearningCampaignEnvironmentSnapshot(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            host: ProcessInfo.processInfo.hostName,
            platform: "macOS",
            machine: ProcessInfo.processInfo.machineHardwareName,
            swiftVersion: commandOutput("/usr/bin/xcrun", arguments: ["swift", "--version"]),
            xcodebuildVersion: commandOutput("/usr/bin/xcodebuild", arguments: ["-version"]),
            destination: processEnvironment["KUYU_XCODE_DESTINATION"] ?? "platform=macOS",
            configuration: processEnvironment["KUYU_XCODE_CONFIGURATION"] ?? "Debug",
            derivedData: processEnvironment["KUYU_XCODE_DERIVED_DATA"] ?? "",
            lockPath: processEnvironment["KUYU_LEARNING_LOCK_PATH"] ?? "",
            repositories: [
                LearningCampaignRepositorySnapshot(
                    path: repositoryPath,
                    head: commandOutput("/usr/bin/git", arguments: ["rev-parse", "HEAD"]),
                    branch: commandOutput("/usr/bin/git", arguments: ["rev-parse", "--abbrev-ref", "HEAD"]),
                    dirty: !commandOutput("/usr/bin/git", arguments: ["status", "--porcelain"]).isEmpty
                ),
            ]
        )
        try write(environment, fileName: "learning-campaign-environment.json", root: root)
    }

    private func commandOutput(_ executablePath: String, arguments: [String]) -> String {
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return "unavailable"
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return "unavailable"
        }
    }

    private func writeResourceSampleIfNeeded(
        plan: LearningCampaignPlan,
        root: URL
    ) throws {
        guard (plan.resourceSampleSeconds ?? 30) > 0 else { return }
        let values = try FileManager.default.attributesOfFileSystem(forPath: root.path)
        let freeBytes = (values[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        let sample = LearningCampaignResourceSnapshot(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            artifactRootFreeBytes: freeBytes,
            artifactRootUsedBytes: 0,
            loadAverage1m: 0
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(sample)
        data.append(Data("\n".utf8))
        try data.write(
            to: root.appendingPathComponent("resource-samples.jsonl"),
            options: [.atomic]
        )
    }
}

private struct LearningCampaignProgressEvent: Codable {
    let event: String
    let timestamp: Date
    let status: String?
    let exitCode: Int?
}

private struct LearningCampaignEnvironmentSnapshot: Encodable {
    let timestamp: String
    let host: String
    let platform: String
    let machine: String
    let swiftVersion: String
    let xcodebuildVersion: String
    let destination: String
    let configuration: String
    let derivedData: String
    let lockPath: String
    let repositories: [LearningCampaignRepositorySnapshot]
}

private struct LearningCampaignRepositorySnapshot: Encodable {
    let path: String
    let head: String
    let branch: String
    let dirty: Bool
}

private struct LearningCampaignResourceSnapshot: Encodable {
    let timestamp: String
    let artifactRootFreeBytes: Int64
    let artifactRootUsedBytes: Int64
    let loadAverage1m: Double
}

private extension ProcessInfo {
    var machineHardwareName: String {
        environment["HOSTTYPE"] ?? "unknown"
    }
}
