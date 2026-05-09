import Foundation
import KuyuMLX
import KuyuTraining

public struct LearningCampaignProgressRecord: Codable, Sendable, Equatable {
    public let event: String
    public let timestamp: String
    public let status: String?
    public let exitCode: Int?

    public init(event: String, timestamp: String, status: String?, exitCode: Int?) {
        self.event = event
        self.timestamp = timestamp
        self.status = status
        self.exitCode = exitCode
    }
}

public struct LearningCampaignGenerationState: Identifiable, Sendable, Equatable {
    public let id: String
    public let seed: String
    public let generationIndex: Int
    public let accepted: Bool
    public let incumbentImproved: Bool
    public let bestCandidateID: String?
    public let bestFitness: Double?
    public let incumbentFitness: Double?
    public let bestVsIncumbentDelta: Double?
    public let minimumImprovementOverIncumbent: Double?
    public let mutationRate: Double
    public let mutationNoiseScale: Double
    public let eliteCandidateIDs: [String]
    public let candidateCount: Int
    public let evaluatedCandidateCount: Int
    public let rejectionReasons: [String]
    public let createdAt: Date

    init(seed: String, record: PopulationGenerationRecord) {
        self.id = "\(seed)-\(record.runID)-\(record.generationIndex)"
        self.seed = seed
        self.generationIndex = record.generationIndex
        self.accepted = record.accepted
        self.incumbentImproved = record.incumbentImproved
        self.bestCandidateID = record.bestCandidateID
        self.bestFitness = record.bestFitness
        self.incumbentFitness = record.incumbentFitness
        self.bestVsIncumbentDelta = record.bestVsIncumbentDelta
        self.minimumImprovementOverIncumbent = record.minimumImprovementOverIncumbent
        self.mutationRate = record.mutationRate
        self.mutationNoiseScale = record.mutationNoiseScale
        self.eliteCandidateIDs = record.eliteCandidateIDs
        self.candidateCount = record.candidateCount
        self.evaluatedCandidateCount = record.evaluatedCandidateCount
        self.rejectionReasons = record.rejectionReasons
        self.createdAt = record.createdAt
    }
}

public struct LearningCampaignCandidateState: Identifiable, Sendable, Equatable {
    public let id: String
    public let seed: String
    public let generationIndex: Int
    public let candidateID: String
    public let parentCandidateIDs: [String]
    public let mutationSummary: String?
    public let scalarFitness: Double?
    public let rewardAverage: Double?
    public let taskPassRate: Double?
    public let requestedConcurrency: Int?
    public let activeEvaluationCountAtStart: Int?
    public let durationSeconds: Double?
    public let isIncumbent: Bool

    init(
        seed: String,
        candidate: GenomeCandidate,
        fitness: FitnessSummary?,
        trace: EvolutionCandidateEvaluationTrace?
    ) {
        self.id = "\(seed)-\(candidate.runID)-\(candidate.candidateID)"
        self.seed = seed
        self.generationIndex = candidate.generationIndex
        self.candidateID = candidate.candidateID
        self.parentCandidateIDs = candidate.parentCandidateIDs
        self.mutationSummary = candidate.mutationSummary
        self.scalarFitness = fitness?.scalarFitness
        self.rewardAverage = fitness?.rewardAverage
        self.taskPassRate = fitness?.taskPassRate
        self.requestedConcurrency = trace?.requestedConcurrency
        self.activeEvaluationCountAtStart = trace?.activeEvaluationCountAtStart
        self.durationSeconds = trace?.durationSeconds
        self.isIncumbent = candidate.isIncumbent == true
    }
}

public struct LearningCampaignAutonomyStageState: Identifiable, Sendable, Equatable {
    public let id: String
    public let stageID: String
    public let kind: String
    public let status: String
    public let satisfiedGateCount: Int
    public let requiredEvidenceCount: Int
    public let failureReasons: [String]

    init(record: AutonomousTrainingStageExecutionRecord) {
        self.id = record.stageID
        self.stageID = record.stageID
        self.kind = record.kind.rawValue
        self.status = record.status.rawValue
        self.satisfiedGateCount = record.satisfiedGates.count
        self.requiredEvidenceCount = record.evidence.count
        self.failureReasons = record.failureReasons
    }
}

public struct LearningCampaignRunStoreState: Sendable, Equatable {
    public let artifactDirectory: URL
    public let plan: LearningCampaignPlan?
    public let status: LearningCampaignStatus?
    public let summary: LearningCampaignSummary?
    public let validation: LearningCampaignValidation?
    public let retention: LearningCampaignArtifactRetentionSummary?
    public let progressEvents: [LearningCampaignProgressRecord]
    public let generations: [LearningCampaignGenerationState]
    public let candidates: [LearningCampaignCandidateState]

    public var latestEvent: LearningCampaignProgressRecord? {
        progressEvents.last
    }

    public var task: String {
        plan?.task ?? "--"
    }

    public var suiteSummary: String {
        guard let plan else { return "--" }
        return plan.suites.joined(separator: ",")
    }

    public var seedCount: Int {
        summary?.seedCount ?? plan?.seeds.count ?? 0
    }

    public var acceptedCount: Int {
        summary?.acceptedCount ?? generations.filter(\.accepted).count
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

    public var maxRequestedCandidateConcurrency: Int {
        candidates.compactMap(\.requestedConcurrency).max() ?? plan?.candidateEvaluationConcurrency ?? 1
    }

    public var maxActiveCandidateEvaluations: Int {
        candidates.compactMap(\.activeEvaluationCountAtStart).max() ?? 0
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
        guard candidateEvaluationCount > 0 else { return "--" }
        return "\(maxActiveCandidateEvaluations)/\(maxRequestedCandidateConcurrency) active"
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

    public var failureReasons: [String] {
        var reasons: [String] = []
        appendValidationFailureReasons(to: &reasons)
        appendGenerationFailureReasons(to: &reasons)
        appendAutonomyFailureReasons(to: &reasons)
        appendStatusFailureReasons(to: &reasons)
        return unique(reasons)
    }

    public var primaryFailureReason: String? {
        failureReasons.first
    }

    public var diagnosticText: String {
        var lines: [String] = [
            "artifactRoot=\(artifactDirectory.path)",
            "status=\(statusLabel)",
            "validation=\(validationLabel)",
            "task=\(task)",
            "suites=\(suiteSummary)",
            "seeds=\(seedCount)",
            "accepted=\(acceptedCount)",
            "parallelism=\(actualParallelismLabel)"
        ]
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

    private func appendValidationFailureReasons(to reasons: inout [String]) {
        guard let validation, !validation.valid else { return }
        if validation.issues.isEmpty {
            reasons.append("validation: invalid without typed issue")
            return
        }
        reasons.append(contentsOf: validation.issues.map(validationReason))
    }

    private func validationReason(_ issue: LearningCampaignValidationIssue) -> String {
        switch issue.code {
        case "parent-task-evaluation-quality-failed":
            return "Initial parent checkpoint failed task quality: \(issue.detail)"
        case "parent-task-regression-failed":
            return "Initial parent checkpoint failed regression: \(issue.detail)"
        case "missing-parent-task-regression":
            return "Initial parent regression artifact is missing: \(issue.detail)"
        default:
            return "validation:\(issue.code): \(issue.detail)"
        }
    }

    private func appendGenerationFailureReasons(to reasons: inout [String]) {
        for generation in generations {
            for reason in generation.rejectionReasons {
                reasons.append("generation:\(generation.seed):g\(generation.generationIndex): \(reason)")
            }
        }
    }

    private func appendAutonomyFailureReasons(to reasons: inout [String]) {
        for stage in autonomyStages {
            for reason in stage.failureReasons {
                reasons.append("autonomy:\(stage.stageID): \(reason)")
            }
        }
    }

    private func appendStatusFailureReasons(to reasons: inout [String]) {
        let label = statusLabel.lowercased()
        if label == "failed" || label == "cancelled" {
            reasons.append("status: \(statusLabel)")
        }
        if let event = latestEvent {
            let eventText = event.event.lowercased()
            let eventStatus = event.status?.lowercased()
            if eventText.contains("fail") || eventStatus == "failed" {
                reasons.append("event:\(event.timestamp): \(event.event)")
            }
            if let exitCode = event.exitCode, exitCode != 0 {
                reasons.append("exitCode: \(exitCode)")
            }
        }
    }

    private func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            result.append(trimmed)
        }
        return result
    }
}

public struct LearningCampaignRunStore {
    public init() {}

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
            progressEvents: try decodeJSONLines(
                LearningCampaignProgressRecord.self,
                from: artifactDirectory.appendingPathComponent("progress.jsonl")
            ),
            generations: try loadGenerations(from: artifactDirectory),
            candidates: try loadCandidates(from: artifactDirectory)
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
            modelDescriptor: manifest.descriptorID,
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

    private func decodeJSONLines<T: Decodable>(_ type: T.Type, from url: URL) throws -> [T] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let text = try String(contentsOf: url, encoding: .utf8)
        var records: [T] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let data = Data(trimmed.utf8)
            records.append(try decoder.decode(type, from: data))
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
