import Foundation
import KuyuMLX
import KuyuMLXCampaignContracts
import KuyuTraining

public enum LearningCampaignVectorizedBatchKind: String, Sendable, Codable, Equatable {
    case variation
    case evaluation
}

public struct LearningCampaignVectorizedBatchState: Identifiable, Sendable, Equatable {
    public let id: String
    public let kind: LearningCampaignVectorizedBatchKind
    public let seed: String
    public let generationIndex: Int
    public let candidateCount: Int
    public let completedCandidateCount: Int
    public let elapsedSeconds: Double
    public let acceleratorDevice: String
    public let policyExecutionMode: String?
    public let observationExecutionMode: String?
    public let worldExecutionMode: String?
    public let actionEncoding: String?
    public let worldActiveActionDimension: Int?
    public let artifactPath: String
    public let bestFitness: Double?

    init(
        kind: LearningCampaignVectorizedBatchKind,
        seed: String,
        generationIndex: Int,
        candidateCount: Int,
        completedCandidateCount: Int,
        elapsedSeconds: Double,
        acceleratorDevice: String,
        policyExecutionMode: String?,
        observationExecutionMode: String?,
        worldExecutionMode: String?,
        actionEncoding: String?,
        worldActiveActionDimension: Int?,
        artifactPath: String,
        bestFitness: Double?
    ) {
        self.id = "\(kind.rawValue)-\(seed)-g\(generationIndex)-\(artifactPath)"
        self.kind = kind
        self.seed = seed
        self.generationIndex = generationIndex
        self.candidateCount = candidateCount
        self.completedCandidateCount = completedCandidateCount
        self.elapsedSeconds = elapsedSeconds
        self.acceleratorDevice = acceleratorDevice
        self.policyExecutionMode = policyExecutionMode
        self.observationExecutionMode = observationExecutionMode
        self.worldExecutionMode = worldExecutionMode
        self.actionEncoding = actionEncoding
        self.worldActiveActionDimension = worldActiveActionDimension
        self.artifactPath = artifactPath
        self.bestFitness = bestFitness
    }

    public var executionSummary: String {
        switch kind {
        case .variation:
            return "mlx-stacked-variation"
        case .evaluation:
            let policy = policyExecutionMode ?? "unknown-policy"
            let observation = observationExecutionMode ?? "unknown-observation"
            let world = worldExecutionMode ?? "unknown-world"
            let action = actionEncoding ?? "unknown-action"
            if let worldActiveActionDimension {
                return "\(policy) / \(observation) / \(world) / \(action) active=\(worldActiveActionDimension)"
            }
            return "\(policy) / \(observation) / \(world) / \(action)"
        }
    }
}

public struct LearningCampaignRunStoreState: Sendable, Equatable {
    /// The runtime-owned progress snapshot is built once from the artifact
    /// records before the state crosses into SwiftUI.
    public let artifactDirectory: URL
    public let plan: LearningCampaignPlan?
    public let status: LearningCampaignStatus?
    public let summary: LearningCampaignSummary?
    public let validation: LearningCampaignValidation?
    public let retention: LearningCampaignArtifactRetentionSummary?
    public let accelerator: LearningCampaignAcceleratorSnapshot?
    public let vectorizedBatches: [LearningCampaignVectorizedBatchState]
    public let progress: LearningCampaignProgressSnapshot

    public init(
        artifactDirectory: URL,
        plan: LearningCampaignPlan?,
        status: LearningCampaignStatus?,
        summary: LearningCampaignSummary?,
        validation: LearningCampaignValidation?,
        retention: LearningCampaignArtifactRetentionSummary?,
        accelerator: LearningCampaignAcceleratorSnapshot?,
        progressEvents: [LearningCampaignProgressEvent],
        generations: [LearningCampaignGenerationState],
        candidates: [LearningCampaignCandidateState],
        vectorizedBatches: [LearningCampaignVectorizedBatchState],
        acceptedCheckpoints: [LearningCampaignAcceptedCheckpointState]
    ) {
        self.artifactDirectory = artifactDirectory
        self.plan = plan
        self.status = status
        self.summary = summary
        self.validation = validation
        self.retention = retention
        self.accelerator = accelerator
        self.vectorizedBatches = vectorizedBatches
        self.progress = LearningCampaignProgressSnapshot(
            plan: plan,
            status: status,
            summary: summary,
            validation: validation,
            progressEvents: progressEvents,
            generations: generations,
            candidates: candidates,
            acceptedCheckpoints: acceptedCheckpoints
        )
    }

    public var progressEvents: [LearningCampaignProgressEvent] {
        progress.progressEvents
    }

    public var generations: [LearningCampaignGenerationState] {
        progress.generations
    }

    public var candidates: [LearningCampaignCandidateState] {
        progress.candidates
    }

    public var acceptedCheckpoints: [LearningCampaignAcceptedCheckpointState] {
        progress.acceptedCheckpoints
    }

    public var latestEvent: LearningCampaignProgressEvent? {
        progressEvents.last
    }

    public var task: String {
        plan?.task ?? "--"
    }

    public var trainingStageLabel: String {
        if let displayName = plan?.trainingStageDisplayName, !displayName.isEmpty {
            return displayName
        }
        if let stageID = plan?.trainingStageID, !stageID.isEmpty {
            return stageID
        }
        return "--"
    }

    public var trainingStageKindLabel: String {
        plan?.trainingStageKind?.rawValue ?? "--"
    }

    public var hasTrainingStageIdentity: Bool {
        trainingStageLabel != "--" || trainingStageKindLabel != "--"
    }

    public var suiteSummary: String {
        guard let plan else { return "--" }
        return plan.suites.joined(separator: ",")
    }

    public var seedCount: Int {
        summary?.seedCount ?? plan?.seeds.count ?? 0
    }

    public var acceptedCount: Int {
        if let summary {
            return summary.acceptedCount
        }
        return acceptedCheckpoints.filter(\.accepted).count
    }

    public var finalCheckpoint: String? {
        summary?.finalCheckpoint
    }

    public var statusLabel: String {
        status?.status ?? latestEvent?.status ?? "running"
    }

    public var validationLabel: String {
        guard let validation else { return "--" }
        return validation.valid ? "valid" : "invalid"
    }

    public var bestDelta: Double? {
        let deltas = generations.compactMap(\.bestVsIncumbentDelta)
        return deltas.max()
    }

    public var latestGenerations: [LearningCampaignGenerationState] {
        generations
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                if lhs.seed != rhs.seed { return lhs.seed < rhs.seed }
                return lhs.generationIndex > rhs.generationIndex
            }
    }

    public var plannedGenerationCount: Int {
        plan?.generations ?? generations.map(\.generationIndex).max().map { $0 + 1 } ?? 0
    }

    public var latestCompletedGenerationIndex: Int? {
        progress.latestCompletedGenerationIndex
    }

    public var completedGenerationCount: Int {
        latestCompletedGenerationIndex.map { $0 + 1 } ?? generations.count
    }

    public var liveCandidateEvaluationCount: Int {
        progress.liveCandidateEvaluationCount
    }

    public var liveEpisodeCount: Int {
        liveCandidateEvaluationCount * episodeMultiplier
    }

    public var plannedCandidateEvaluationCount: Int {
        if let plan {
            return max(1, plan.seeds.count) * max(1, plan.population) * max(1, plan.generations)
        }
        return max(0, liveCandidateEvaluationCount)
    }

    public var campaignProgressFraction: Double {
        guard status?.status.lowercased() != "succeeded" else { return 1 }
        guard status?.status.lowercased() != "completed" else { return 1 }
        let plannedCandidates = plannedCandidateEvaluationCount
        if plannedCandidates > 0 {
            return min(0.999, max(0, Double(liveCandidateEvaluationCount) / Double(plannedCandidates)))
        }
        let plannedGenerations = plannedGenerationCount
        guard plannedGenerations > 0 else { return 0 }
        return min(0.999, max(0, Double(completedGenerationCount) / Double(plannedGenerations)))
    }

    public var bestFitness: Double? {
        progress.bestFitness
    }

    public var initialBestFitness: Double? {
        progress.initialBestFitness
    }

    public var bestFitnessDeltaFromInitial: Double? {
        guard let bestFitness, let initialBestFitness else { return nil }
        return bestFitness - initialBestFitness
    }

    public var bestTaskPassRate: Double? {
        progress.bestTaskPassRate
    }

    public var bestHoldTimeRatio: Double? {
        progress.bestHoldTimeRatio
    }

    public var bestAltitudeErrorRatio: Double? {
        progress.bestAltitudeErrorRatio
    }

    public var liveBestFitnessSamples: [MetricSample] {
        progress.liveBestFitnessSamples.map { sample in
            MetricSample(time: sample.time, value: sample.value)
        }
    }

    public var liveRewardAverageSamples: [MetricSample] {
        progress.liveRewardAverageSamples.map { sample in
            MetricSample(time: sample.time, value: sample.value)
        }
    }

    public var liveTaskPassRateSamples: [MetricSample] {
        progress.liveTaskPassRateSamples.map { sample in
            MetricSample(time: sample.time, value: sample.value)
        }
    }

    public var liveHoldTimeRatioSamples: [MetricSample] {
        progress.liveHoldTimeRatioSamples.map { sample in
            MetricSample(time: sample.time, value: sample.value)
        }
    }

    public var liveAltitudeErrorRatioSamples: [MetricSample] {
        progress.liveAltitudeErrorRatioSamples.map { sample in
            MetricSample(time: sample.time, value: sample.value)
        }
    }

    public var liveGenerationCountSamples: [MetricSample] {
        progress.liveGenerationCountSamples.map { sample in
            MetricSample(time: sample.time, value: sample.value)
        }
    }

    public var liveEpisodeSamples: [MetricSample] {
        progress.liveEpisodeSamples.map { sample in
            MetricSample(time: sample.time, value: sample.value)
        }
    }

    public var livePopulationDiversitySamples: [MetricSample] {
        progress.livePopulationDiversitySamples.map { sample in
            MetricSample(time: sample.time, value: sample.value)
        }
    }

    public var populationDiversity: Double? {
        progress.livePopulationDiversitySamples.last?.value
    }

    public var latestLiveCandidate: LearningCampaignProgressEvent? {
        progress.latestLiveCandidate
    }

    public var maxRequestedCandidateConcurrency: Int {
        vectorizedBatches.map(\.candidateCount).max()
            ?? candidates.compactMap(\.requestedConcurrency).max()
            ?? plan?.candidateEvaluationConcurrency
            ?? 1
    }

    public var maxActiveCandidateEvaluations: Int {
        vectorizedBatches.map(\.completedCandidateCount).max()
            ?? candidates.compactMap(\.activeEvaluationCountAtStart).max()
            ?? 0
    }

    public var averageCandidateEvaluationDurationSeconds: Double? {
        let durations = candidates.compactMap(\.durationSeconds)
        guard !durations.isEmpty else { return nil }
        return durations.reduce(0, +) / Double(durations.count)
    }

    public var candidateEvaluationCount: Int {
        candidates.count
    }

    public var actualParallelismLabel: String {
        if let batch = latestVectorizedBatch {
            return "\(batch.completedCandidateCount)/\(batch.candidateCount) \(batch.kind.rawValue)"
        }
        guard candidateEvaluationCount > 0 else { return "--" }
        return "\(maxActiveCandidateEvaluations)/\(maxRequestedCandidateConcurrency) active"
    }

    public var latestVectorizedBatch: LearningCampaignVectorizedBatchState? {
        vectorizedBatches.max { lhs, rhs in
            if lhs.generationIndex != rhs.generationIndex {
                return lhs.generationIndex < rhs.generationIndex
            }
            return lhs.artifactPath < rhs.artifactPath
        }
    }

    public var latestAcceleratorDevice: String? {
        latestVectorizedBatch?.acceleratorDevice ?? accelerator?.acceleratorLabel
    }

    public func candidates(
        seed: String,
        generationIndex: Int
    ) -> [LearningCampaignCandidateState] {
        candidates
            .filter { $0.seed == seed && $0.generationIndex == generationIndex }
            .sorted { lhs, rhs in
                let lhsFitness = lhs.scalarFitness ?? -.greatestFiniteMagnitude
                let rhsFitness = rhs.scalarFitness ?? -.greatestFiniteMagnitude
                if lhsFitness != rhsFitness { return lhsFitness > rhsFitness }
                return lhs.candidateID < rhs.candidateID
            }
    }

    public var autonomyStages: [LearningCampaignAutonomyStageState] {
        summary?.autonomousPipelineExecution?.stageRecords.map(LearningCampaignAutonomyStageState.init) ?? []
    }

    public var autonomyPipelineSummary: String {
        let stages = autonomyStages
        guard !stages.isEmpty else { return "--" }
        let completed = stages.filter { $0.status == AutonomousTrainingStageExecutionStatus.completed.rawValue }.count
        let blocked = stages.filter { $0.status == AutonomousTrainingStageExecutionStatus.blocked.rawValue }.count
        if blocked > 0 {
            return "\(completed)/\(stages.count) completed, \(blocked) blocked"
        }
        return "\(completed)/\(stages.count) completed"
    }

    public var isActive: Bool {
        let label = statusLabel.lowercased()
        return label == "running" || label == "started"
    }

    public var diagnosis: LearningCampaignRunDiagnosis {
        progress.diagnosis
    }

    public var failureReasons: [String] {
        diagnosis.reasons
    }

    public var primaryFailureReason: String? {
        diagnosis.primaryIssue
    }

    public var diagnosticText: String {
        var lines: [String] = [
            "artifactRoot=\(artifactDirectory.path)",
            "status=\(statusLabel)",
            "validation=\(validationLabel)",
            "task=\(task)",
            "trainingStage=\(trainingStageLabel)",
            "trainingStageKind=\(trainingStageKindLabel)",
            "suites=\(suiteSummary)",
            "seeds=\(seedCount)",
            "accepted=\(acceptedCount)",
            "parallelism=\(actualParallelismLabel)"
        ]
        if let latestAcceleratorDevice {
            lines.append("accelerator=\(latestAcceleratorDevice)")
        }
        if let latestVectorizedBatch {
            lines.append("vectorizedExecution=\(latestVectorizedBatch.executionSummary)")
        }
        if !vectorizedBatches.isEmpty {
            lines.append("vectorizedBatches=\(vectorizedBatches.count)")
        }
        if let finalCheckpoint {
            lines.append("finalCheckpoint=\(finalCheckpoint)")
        }
        if let latestEvent {
            lines.append("latestEvent=\(latestEvent.timestamp) \(latestEvent.event)")
            if let status = latestEvent.status {
                lines.append("latestEventStatus=\(status)")
            }
            if let exitCode = latestEvent.exitCode {
                lines.append("latestEventExitCode=\(exitCode)")
            }
        }
        let reasons = failureReasons
        if !reasons.isEmpty {
            lines.append("failureReasons:")
            lines.append(contentsOf: reasons.map { "- \($0)" })
        }
        return lines.joined(separator: "\n")
    }

    private var episodeMultiplier: Int {
        let episodeCount = plan?.episodes ?? 1
        let suiteCount = plan?.suites.count ?? 1
        return max(1, episodeCount) * max(1, suiteCount)
    }
}

public struct LearningCampaignRunStore {
    private let artifactReader: any KuyuUITrainingArtifactReading

    public init(
        artifactReader: any KuyuUITrainingArtifactReading = KuyuUITrainingArtifactReader()
    ) {
        self.artifactReader = artifactReader
    }

    public func load(from artifactDirectory: URL) throws -> LearningCampaignRunStoreState {
        let decodedPlan: LearningCampaignPlan? = try decodeIfPresent(
            LearningCampaignPlan.self,
            from: artifactDirectory.appendingPathComponent("learning-campaign-plan.json")
        )
        let evolutionManifest: EvolutionRunManifest? = try decodeIfPresent(
            EvolutionRunManifest.self,
            from: artifactDirectory.appendingPathComponent("evolution-manifest.json")
        )
        let plan = decodedPlan ?? makePlanFallback(
            artifactDirectory: artifactDirectory,
            manifest: evolutionManifest
        )
        let decodedStatus: LearningCampaignStatus? = try decodeIfPresent(
            LearningCampaignStatus.self,
            from: artifactDirectory.appendingPathComponent("campaign-status.json")
        )
        let status = decodedStatus ?? makeStatusFallback(manifest: evolutionManifest)
        let summary: LearningCampaignSummary? = try decodeIfPresent(
            LearningCampaignSummary.self,
            from: artifactDirectory.appendingPathComponent("learning-campaign-summary.json")
        )
        let validation: LearningCampaignValidation? = try decodeIfPresent(
            LearningCampaignValidation.self,
            from: artifactDirectory.appendingPathComponent("learning-campaign-validation.json")
        )
        let retention: LearningCampaignArtifactRetentionSummary? = try decodeIfPresent(
            LearningCampaignArtifactRetentionSummary.self,
            from: artifactDirectory.appendingPathComponent("artifact-retention.json")
        )

        return LearningCampaignRunStoreState(
            artifactDirectory: artifactDirectory,
            plan: plan,
            status: status,
            summary: summary,
            validation: validation,
            retention: retention ?? summary?.retention,
            accelerator: try decodeIfPresent(
                LearningCampaignAcceleratorSnapshot.self,
                from: artifactDirectory.appendingPathComponent("accelerator-snapshot.json")
            ),
            progressEvents: try decodeJSONLines(
                LearningCampaignProgressEvent.self,
                from: artifactDirectory.appendingPathComponent("progress.jsonl"),
                allowsTrailingPartialLine: true
            ),
            generations: try loadGenerations(from: artifactDirectory),
            candidates: try loadCandidates(from: artifactDirectory),
            vectorizedBatches: try artifactReader.validatedVectorizedBatches(in: artifactDirectory),
            acceptedCheckpoints: try loadAcceptedCheckpoints(from: artifactDirectory)
        )
    }

    private func loadAcceptedCheckpoints(from artifactDirectory: URL) throws -> [LearningCampaignAcceptedCheckpointState] {
        var states: [LearningCampaignAcceptedCheckpointState] = []
        if let rootDecision = try loadAcceptedCheckpointDecision(
            seed: "evolution",
            from: artifactDirectory
        ) {
            states.append(rootDecision)
        }

        let seedsRoot = artifactDirectory.appendingPathComponent("seeds", isDirectory: true)
        guard FileManager.default.fileExists(atPath: seedsRoot.path) else {
            return states
        }
        let seedDirectories = try FileManager.default.contentsOfDirectory(
            at: seedsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for seedDirectory in seedDirectories {
            guard try isDirectory(seedDirectory) else { continue }
            if let decision = try loadAcceptedCheckpointDecision(
                seed: seedDirectory.lastPathComponent,
                from: seedDirectory.appendingPathComponent("evolution", isDirectory: true)
            ) {
                states.append(decision)
            }
        }
        return states.sorted { lhs, rhs in
            if lhs.seed != rhs.seed { return lhs.seed < rhs.seed }
            return lhs.id < rhs.id
        }
    }

    private func loadAcceptedCheckpointDecision(
        seed: String,
        from evolutionDirectory: URL
    ) throws -> LearningCampaignAcceptedCheckpointState? {
        let decisionURL = evolutionDirectory.appendingPathComponent(EvolutionAcceptedCheckpointDecision.fileName)
        guard FileManager.default.fileExists(atPath: decisionURL.path) else { return nil }
        let bundle = try artifactReader.validatedEvolutionArtifacts(in: evolutionDirectory)
        return LearningCampaignAcceptedCheckpointState(
            seed: seed,
            decision: bundle.acceptedCheckpoint
        )
    }

    private func loadGenerations(from artifactDirectory: URL) throws -> [LearningCampaignGenerationState] {
        var states: [LearningCampaignGenerationState] = []
        let rootGenerationRecords = try decodeJSONLines(
            PopulationGenerationRecord.self,
            from: artifactDirectory.appendingPathComponent("generations.jsonl")
        )
        if !rootGenerationRecords.isEmpty {
            states.append(contentsOf: rootGenerationRecords.map {
                LearningCampaignGenerationState(seed: "evolution", record: $0)
            })
        }
        let seedsRoot = artifactDirectory.appendingPathComponent("seeds", isDirectory: true)
        guard FileManager.default.fileExists(atPath: seedsRoot.path) else {
            return states.sorted { lhs, rhs in
                if lhs.seed != rhs.seed { return lhs.seed < rhs.seed }
                return lhs.generationIndex < rhs.generationIndex
            }
        }

        let seedDirectories = try FileManager.default.contentsOfDirectory(
            at: seedsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for seedDirectory in seedDirectories {
            guard try isDirectory(seedDirectory) else { continue }
            let records = try decodeJSONLines(
                PopulationGenerationRecord.self,
                from: seedDirectory
                    .appendingPathComponent("evolution", isDirectory: true)
                    .appendingPathComponent("generations.jsonl")
            )
            let seed = seedDirectory.lastPathComponent
            states.append(contentsOf: records.map { LearningCampaignGenerationState(seed: seed, record: $0) })
        }
        return states.sorted { lhs, rhs in
            if lhs.seed != rhs.seed { return lhs.seed < rhs.seed }
            return lhs.generationIndex < rhs.generationIndex
        }
    }

    private func loadCandidates(from artifactDirectory: URL) throws -> [LearningCampaignCandidateState] {
        var states: [LearningCampaignCandidateState] = []
        states.append(contentsOf: try loadCandidateStates(
            from: artifactDirectory,
            seed: "evolution"
        ))

        let seedsRoot = artifactDirectory.appendingPathComponent("seeds", isDirectory: true)
        guard FileManager.default.fileExists(atPath: seedsRoot.path) else {
            return states
        }
        let seedDirectories = try FileManager.default.contentsOfDirectory(
            at: seedsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for seedDirectory in seedDirectories {
            guard try isDirectory(seedDirectory) else { continue }
            states.append(contentsOf: try loadCandidateStates(
                from: seedDirectory.appendingPathComponent("evolution", isDirectory: true),
                seed: seedDirectory.lastPathComponent
            ))
        }
        return states
    }

    private func loadCandidateStates(
        from evolutionDirectory: URL,
        seed: String
    ) throws -> [LearningCampaignCandidateState] {
        let candidates = try decodeJSONLines(
            GenomeCandidate.self,
            from: evolutionDirectory.appendingPathComponent("candidates.jsonl")
        )
        guard !candidates.isEmpty else { return [] }
        let fitness = try decodeJSONLines(
            FitnessSummary.self,
            from: evolutionDirectory.appendingPathComponent("fitness.jsonl")
        )
        let traces = try decodeJSONLines(
            EvolutionCandidateEvaluationTrace.self,
            from: evolutionDirectory.appendingPathComponent("evaluation-trace.jsonl")
        )
        let fitnessByCandidate = Dictionary(uniqueKeysWithValues: fitness.map { ($0.candidateID, $0) })
        let traceByCandidate = Dictionary(uniqueKeysWithValues: traces.map { ($0.candidateID, $0) })
        return candidates.map { candidate in
            LearningCampaignCandidateState(
                seed: seed,
                candidate: candidate,
                fitness: fitnessByCandidate[candidate.candidateID],
                trace: traceByCandidate[candidate.candidateID]
            )
        }
    }

    private func makePlanFallback(
        artifactDirectory: URL,
        manifest: EvolutionRunManifest?
    ) -> LearningCampaignPlan? {
        guard let manifest else { return nil }
        return LearningCampaignPlan(
            artifactRoot: artifactDirectory.path,
            task: manifest.taskID,
            suites: ["evolution"],
            episodes: 1,
            workers: manifest.workerCount,
            population: manifest.populationSize,
            generations: manifest.generationCount,
            eliteCount: manifest.eliteCount,
            candidateEvaluationConcurrency: manifest.candidateEvaluationConcurrency,
            seeds: ["evolution"],
            sourceCheckpoint: nil,
            robotManifest: manifest.robotManifestID,
            variation: "evolution",
            searchStrategy: manifest.searchStrategy.rawValue,
            mutationRate: manifest.mutationRate,
            mutationNoiseScale: manifest.mutationNoiseScale,
            bootstrapSuite: "",
            bootstrapEpisodes: 0,
            bootstrapSequence: 0,
            bootstrapEpochs: 0,
            bootstrapMaxBatches: 0,
            bootstrapLearningRate: 0,
            bootstrapRepairAttempts: nil,
            verifyParentTask: false,
            resumeEnabled: false,
            resourceSampleSeconds: nil,
            artifactRetentionPolicy: .full,
            availableDiskBytes: 0,
            requiredDiskBytes: 0,
            plannedCandidateEvaluations: manifest.populationSize * manifest.generationCount,
            plannedRegressionRollouts: manifest.populationSize * manifest.generationCount,
            plannedRegressionEpisodes: manifest.populationSize * manifest.generationCount
        )
    }

    private func makeStatusFallback(manifest: EvolutionRunManifest?) -> LearningCampaignStatus? {
        guard let manifest else { return nil }
        return LearningCampaignStatus(
            status: manifest.terminalState.rawValue,
            exitCode: manifest.terminalState == .completed ? 0 : 1,
            startedAt: ISO8601DateFormatter().string(from: manifest.startedAt),
            finishedAt: manifest.completedAt.map { ISO8601DateFormatter().string(from: $0) } ?? ""
        )
    }

    private func decodeIfPresent<T: Decodable>(_ type: T.Type, from url: URL) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try decoder.decode(type, from: data)
    }

    private func decodeJSONLines<T: Decodable>(
        _ type: T.Type,
        from url: URL,
        allowsTrailingPartialLine: Bool = false
    ) throws -> [T] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let text = try String(contentsOf: url, encoding: .utf8)
        let rawLines = text.split(whereSeparator: \.isNewline)
        var records: [T] = []
        for (index, line) in rawLines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let data = Data(trimmed.utf8)
            do {
                records.append(try decoder.decode(type, from: data))
            } catch {
                let isLastLine = index == rawLines.index(before: rawLines.endIndex)
                if allowsTrailingPartialLine && isLastLine && !text.hasSuffix("\n") {
                    continue
                }
                throw error
            }
        }
        return records
    }

    private func isDirectory(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        return values.isDirectory == true
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        return decoder
    }
}
