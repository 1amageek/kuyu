import Foundation
import KuyuMLX
import KuyuTraining

public struct LearningCampaignProgressRecord: Codable, Sendable, Equatable {
    public let event: String
    public let timestamp: String
    public let status: String?
    public let exitCode: Int?
    public let phase: String?
    public let seed: String?
    public let generationIndex: Int?
    public let candidateID: String?
    public let fitness: Double?
    public let rewardAverage: Double?
    public let taskPassRate: Double?
    public let safetyViolationRate: Double?
    public let holdTimeRatio: Double?
    public let altitudeErrorRatio: Double?
    public let workerThroughput: Double?
    public let gpuAcceleration: Bool?
    public let tensorWorldBatch: Bool?
    public let tensorSummary: Bool?
    public let vectorizedPopulationSize: Int?
    public let vectorizedWorldCount: Int?
    public let vectorizedHistoryLength: Int?
    public let vectorizedObservationDimension: Int?
    public let vectorizedActionDimension: Int?
    public let failureReasons: [String]?
    public let bestCandidateID: String?
    public let accepted: Bool?
    public let path: String?
    public let message: String?

    public init(
        event: String,
        timestamp: String,
        status: String?,
        exitCode: Int?,
        phase: String? = nil,
        seed: String? = nil,
        generationIndex: Int? = nil,
        candidateID: String? = nil,
        fitness: Double? = nil,
        rewardAverage: Double? = nil,
        taskPassRate: Double? = nil,
        safetyViolationRate: Double? = nil,
        holdTimeRatio: Double? = nil,
        altitudeErrorRatio: Double? = nil,
        workerThroughput: Double? = nil,
        gpuAcceleration: Bool? = nil,
        tensorWorldBatch: Bool? = nil,
        tensorSummary: Bool? = nil,
        vectorizedPopulationSize: Int? = nil,
        vectorizedWorldCount: Int? = nil,
        vectorizedHistoryLength: Int? = nil,
        vectorizedObservationDimension: Int? = nil,
        vectorizedActionDimension: Int? = nil,
        failureReasons: [String] = [],
        bestCandidateID: String? = nil,
        accepted: Bool? = nil,
        path: String? = nil,
        message: String? = nil
    ) {
        self.event = event
        self.timestamp = timestamp
        self.status = status
        self.exitCode = exitCode
        self.phase = phase
        self.seed = seed
        self.generationIndex = generationIndex
        self.candidateID = candidateID
        self.fitness = fitness
        self.rewardAverage = rewardAverage
        self.taskPassRate = taskPassRate
        self.safetyViolationRate = safetyViolationRate
        self.holdTimeRatio = holdTimeRatio
        self.altitudeErrorRatio = altitudeErrorRatio
        self.workerThroughput = workerThroughput
        self.gpuAcceleration = gpuAcceleration
        self.tensorWorldBatch = tensorWorldBatch
        self.tensorSummary = tensorSummary
        self.vectorizedPopulationSize = vectorizedPopulationSize
        self.vectorizedWorldCount = vectorizedWorldCount
        self.vectorizedHistoryLength = vectorizedHistoryLength
        self.vectorizedObservationDimension = vectorizedObservationDimension
        self.vectorizedActionDimension = vectorizedActionDimension
        self.failureReasons = failureReasons
        self.bestCandidateID = bestCandidateID
        self.accepted = accepted
        self.path = path
        self.message = message
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
    public let holdTimeRatio: Double?
    public let altitudeErrorRatio: Double?
    public let requestedConcurrency: Int?
    public let activeEvaluationCountAtStart: Int?
    public let durationSeconds: Double?
    public let isIncumbent: Bool
    public let checkpointPath: String?

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
        self.holdTimeRatio = fitness?.holdTimeRatio
        self.altitudeErrorRatio = fitness?.altitudeErrorRatio
        self.requestedConcurrency = trace?.requestedConcurrency
        self.activeEvaluationCountAtStart = trace?.activeEvaluationCountAtStart
        self.durationSeconds = trace?.durationSeconds
        self.isIncumbent = candidate.isIncumbent == true
        self.checkpointPath = candidate.checkpointURL?.path
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

public struct LearningCampaignAcceptedCheckpointState: Identifiable, Sendable, Equatable {
    public let id: String
    public let seed: String
    public let accepted: Bool
    public let candidateID: String?
    public let bestCandidateID: String?
    public let bestFitness: Double?
    public let incumbentCandidateID: String?
    public let incumbentFitness: Double?
    public let bestVsIncumbentDelta: Double?
    public let minimumImprovementOverIncumbent: Double?
    public let publishMetricRegressions: [String]
    public let reasons: [String]

    init(seed: String, decision: EvolutionAcceptedCheckpointDecision) {
        self.id = "\(seed)-\(decision.runID)"
        self.seed = seed
        self.accepted = decision.accepted
        self.candidateID = decision.candidateID
        self.bestCandidateID = decision.bestCandidateID
        self.bestFitness = decision.bestFitness
        self.incumbentCandidateID = decision.incumbentCandidateID
        self.incumbentFitness = decision.incumbentFitness
        self.bestVsIncumbentDelta = decision.bestVsIncumbentDelta
        self.minimumImprovementOverIncumbent = decision.minimumImprovementOverIncumbent
        self.publishMetricRegressions = decision.publishMetricRegressions
        self.reasons = decision.reasons
    }
}

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
    /// Metrics that require O(N) passes over progress events, generations,
    /// and candidates. They are computed exactly once at construction time
    /// (off the main actor, inside the store load) so that SwiftUI body
    /// evaluations reading them stay O(1).
    public struct DerivedMetrics: Sendable, Equatable {
        public let latestCompletedGenerationIndex: Int?
        public let liveCandidateEvaluationCount: Int
        public let bestFitness: Double?
        public let initialBestFitness: Double?
        public let bestTaskPassRate: Double?
        public let bestHoldTimeRatio: Double?
        public let bestAltitudeErrorRatio: Double?
        public let liveBestFitnessSamples: [MetricSample]
        public let liveRewardAverageSamples: [MetricSample]
        public let liveTaskPassRateSamples: [MetricSample]
        public let liveHoldTimeRatioSamples: [MetricSample]
        public let liveAltitudeErrorRatioSamples: [MetricSample]
        public let liveGenerationCountSamples: [MetricSample]
        public let liveEpisodeSamples: [MetricSample]
        public let livePopulationDiversitySamples: [MetricSample]
        public let latestLiveCandidate: LearningCampaignProgressRecord?
        public let diagnosis: LearningCampaignRunDiagnosis

        init(
            plan: LearningCampaignPlan?,
            status: LearningCampaignStatus?,
            summary: LearningCampaignSummary?,
            validation: LearningCampaignValidation?,
            progressEvents: [LearningCampaignProgressRecord],
            generations: [LearningCampaignGenerationState],
            candidates: [LearningCampaignCandidateState],
            acceptedCheckpoints: [LearningCampaignAcceptedCheckpointState]
        ) {
            let persistedGenerationIndex = generations.map(\.generationIndex).max()
            let liveGenerationIndex = progressEvents
                .filter { $0.event == "generation-completed" }
                .compactMap(\.generationIndex)
                .max()
            switch (persistedGenerationIndex, liveGenerationIndex) {
            case (.some(let lhs), .some(let rhs)):
                latestCompletedGenerationIndex = max(lhs, rhs)
            case (.some(let value), .none), (.none, .some(let value)):
                latestCompletedGenerationIndex = value
            case (.none, .none):
                latestCompletedGenerationIndex = nil
            }

            let progressCandidateCount = progressEvents.filter { $0.event == "candidate-evaluated" }.count
            liveCandidateEvaluationCount = max(candidates.count, progressCandidateCount)

            bestFitness = Self.mergedExtremum(
                persisted: candidates.compactMap(\.scalarFitness).max(),
                live: progressEvents.compactMap(\.fitness).max(),
                by: max
            )
            let generationZeroLiveFitness = progressEvents
                .filter { $0.event == "candidate-evaluated" && $0.generationIndex == 0 }
                .compactMap(\.fitness)
                .max()
            initialBestFitness = generationZeroLiveFitness
                ?? candidates.filter { $0.generationIndex == 0 }.compactMap(\.scalarFitness).max()
            bestTaskPassRate = Self.mergedExtremum(
                persisted: candidates.compactMap(\.taskPassRate).max(),
                live: progressEvents.compactMap(\.taskPassRate).max(),
                by: max
            )
            bestHoldTimeRatio = Self.mergedExtremum(
                persisted: candidates.compactMap(\.holdTimeRatio).max(),
                live: progressEvents.compactMap(\.holdTimeRatio).max(),
                by: max
            )
            bestAltitudeErrorRatio = Self.mergedExtremum(
                persisted: candidates.compactMap(\.altitudeErrorRatio).min(),
                live: progressEvents.compactMap(\.altitudeErrorRatio).min(),
                by: min
            )

            let candidateRecords = progressEvents.filter { record in
                record.event == "candidate-evaluated" &&
                record.generationIndex != nil &&
                record.fitness?.isFinite == true
            }
            let recordsByGeneration = Dictionary(grouping: candidateRecords) { record in
                record.generationIndex ?? 0
            }
            let sortedGenerationIndexes = recordsByGeneration.keys.sorted()
            let bestRecordsByGeneration = sortedGenerationIndexes.compactMap { generationIndex in
                recordsByGeneration[generationIndex]?.max { lhs, rhs in
                    (lhs.fitness ?? -.greatestFiniteMagnitude) < (rhs.fitness ?? -.greatestFiniteMagnitude)
                }
            }
            liveBestFitnessSamples = Self.samples(from: bestRecordsByGeneration, value: \.fitness)
            liveRewardAverageSamples = Self.samples(from: bestRecordsByGeneration, value: \.rewardAverage)
            liveTaskPassRateSamples = Self.samples(from: bestRecordsByGeneration, value: \.taskPassRate)
            liveHoldTimeRatioSamples = Self.samples(from: bestRecordsByGeneration, value: \.holdTimeRatio)
            liveAltitudeErrorRatioSamples = Self.samples(from: bestRecordsByGeneration, value: \.altitudeErrorRatio)

            let completedOrEvaluatedGenerationIndexes = Set(
                progressEvents
                    .filter { $0.event == "generation-completed" || $0.event == "candidate-evaluated" }
                    .compactMap(\.generationIndex)
            )
            liveGenerationCountSamples = completedOrEvaluatedGenerationIndexes.sorted().map { generationIndex in
                MetricSample(time: Double(generationIndex), value: Double(generationIndex + 1))
            }

            let episodeMultiplier = max(1, plan?.episodes ?? 1) * max(1, plan?.suites.count ?? 1)
            var cumulativeEpisodes = 0
            liveEpisodeSamples = sortedGenerationIndexes.compactMap { generationIndex in
                guard let records = recordsByGeneration[generationIndex], !records.isEmpty else { return nil }
                cumulativeEpisodes += records.count * episodeMultiplier
                return MetricSample(time: Double(generationIndex), value: Double(cumulativeEpisodes))
            }

            livePopulationDiversitySamples = sortedGenerationIndexes.compactMap { generationIndex in
                guard let records = recordsByGeneration[generationIndex] else { return nil }
                let values = records.compactMap(\.fitness).filter(\.isFinite)
                guard values.count > 1 else { return nil }
                return MetricSample(time: Double(generationIndex), value: Self.standardDeviation(values))
            }

            latestLiveCandidate = progressEvents.last { $0.event == "candidate-evaluated" }

            let autonomyStages = summary?.autonomousPipelineExecution?.stageRecords
                .map(LearningCampaignAutonomyStageState.init) ?? []
            diagnosis = LearningCampaignRunDiagnosis.make(
                status: status,
                validation: validation,
                summary: summary,
                progressEvents: progressEvents.map {
                    LearningCampaignRunDiagnosisProgressEvent(
                        event: $0.event,
                        timestamp: $0.timestamp,
                        status: $0.status,
                        exitCode: $0.exitCode
                    )
                },
                checkpointRejectionReasons: acceptedCheckpoints.flatMap { checkpoint in
                    if checkpoint.accepted {
                        return [String]()
                    }
                    return checkpoint.reasons.map { reason in
                        "accepted-checkpoint:\(checkpoint.seed): \(reason)"
                    }
                },
                generationRejectionReasons: generations.flatMap { generation in
                    generation.rejectionReasons.map { reason in
                        "generation:\(generation.seed):g\(generation.generationIndex): \(reason)"
                    }
                },
                autonomyFailureReasons: autonomyStages.flatMap { stage in
                    stage.failureReasons.map { reason in
                        "autonomy:\(stage.stageID): \(reason)"
                    }
                }
            )
        }

        private static func mergedExtremum(
            persisted: Double?,
            live: Double?,
            by extremum: (Double, Double) -> Double
        ) -> Double? {
            switch (persisted, live) {
            case (.some(let lhs), .some(let rhs)):
                return extremum(lhs, rhs)
            case (.some(let value), .none), (.none, .some(let value)):
                return value
            case (.none, .none):
                return nil
            }
        }

        private static func samples(
            from records: [LearningCampaignProgressRecord],
            value: KeyPath<LearningCampaignProgressRecord, Double?>
        ) -> [MetricSample] {
            records.compactMap { record in
                guard let generationIndex = record.generationIndex,
                      let value = record[keyPath: value] else { return nil }
                return MetricSample(time: Double(generationIndex), value: value)
            }
        }

        private static func standardDeviation(_ values: [Double]) -> Double {
            guard values.count > 1 else { return 0 }
            let average = values.reduce(0, +) / Double(values.count)
            let variance = values.reduce(0) { partial, value in
                let delta = value - average
                return partial + delta * delta
            } / Double(values.count)
            return sqrt(variance)
        }
    }

    public let artifactDirectory: URL
    public let plan: LearningCampaignPlan?
    public let status: LearningCampaignStatus?
    public let summary: LearningCampaignSummary?
    public let validation: LearningCampaignValidation?
    public let retention: LearningCampaignArtifactRetentionSummary?
    public let accelerator: LearningCampaignAcceleratorSnapshot?
    public let progressEvents: [LearningCampaignProgressRecord]
    public let generations: [LearningCampaignGenerationState]
    public let candidates: [LearningCampaignCandidateState]
    public let vectorizedBatches: [LearningCampaignVectorizedBatchState]
    public let acceptedCheckpoints: [LearningCampaignAcceptedCheckpointState]
    public let derived: DerivedMetrics

    public init(
        artifactDirectory: URL,
        plan: LearningCampaignPlan?,
        status: LearningCampaignStatus?,
        summary: LearningCampaignSummary?,
        validation: LearningCampaignValidation?,
        retention: LearningCampaignArtifactRetentionSummary?,
        accelerator: LearningCampaignAcceleratorSnapshot?,
        progressEvents: [LearningCampaignProgressRecord],
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
        self.progressEvents = progressEvents
        self.generations = generations
        self.candidates = candidates
        self.vectorizedBatches = vectorizedBatches
        self.acceptedCheckpoints = acceptedCheckpoints
        self.derived = DerivedMetrics(
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

    public var latestEvent: LearningCampaignProgressRecord? {
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
        derived.latestCompletedGenerationIndex
    }

    public var completedGenerationCount: Int {
        latestCompletedGenerationIndex.map { $0 + 1 } ?? generations.count
    }

    public var liveCandidateEvaluationCount: Int {
        derived.liveCandidateEvaluationCount
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
        derived.bestFitness
    }

    public var initialBestFitness: Double? {
        derived.initialBestFitness
    }

    public var bestFitnessDeltaFromInitial: Double? {
        guard let bestFitness, let initialBestFitness else { return nil }
        return bestFitness - initialBestFitness
    }

    public var bestTaskPassRate: Double? {
        derived.bestTaskPassRate
    }

    public var bestHoldTimeRatio: Double? {
        derived.bestHoldTimeRatio
    }

    public var bestAltitudeErrorRatio: Double? {
        derived.bestAltitudeErrorRatio
    }

    public var liveBestFitnessSamples: [MetricSample] {
        derived.liveBestFitnessSamples
    }

    public var liveRewardAverageSamples: [MetricSample] {
        derived.liveRewardAverageSamples
    }

    public var liveTaskPassRateSamples: [MetricSample] {
        derived.liveTaskPassRateSamples
    }

    public var liveHoldTimeRatioSamples: [MetricSample] {
        derived.liveHoldTimeRatioSamples
    }

    public var liveAltitudeErrorRatioSamples: [MetricSample] {
        derived.liveAltitudeErrorRatioSamples
    }

    public var liveGenerationCountSamples: [MetricSample] {
        derived.liveGenerationCountSamples
    }

    public var liveEpisodeSamples: [MetricSample] {
        derived.liveEpisodeSamples
    }

    public var livePopulationDiversitySamples: [MetricSample] {
        derived.livePopulationDiversitySamples
    }

    public var populationDiversity: Double? {
        derived.livePopulationDiversitySamples.last?.value
    }

    public var latestLiveCandidate: LearningCampaignProgressRecord? {
        derived.latestLiveCandidate
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
        derived.diagnosis
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
    private let artifactVerifier: GeneratedTrainingArtifactCompatibilityVerifier

    public init(
        artifactVerifier: GeneratedTrainingArtifactCompatibilityVerifier = GeneratedTrainingArtifactCompatibilityVerifier()
    ) {
        self.artifactVerifier = artifactVerifier
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
                LearningCampaignProgressRecord.self,
                from: artifactDirectory.appendingPathComponent("progress.jsonl"),
                allowsTrailingPartialLine: true
            ),
            generations: try loadGenerations(from: artifactDirectory),
            candidates: try loadCandidates(from: artifactDirectory),
            vectorizedBatches: try loadVectorizedBatches(from: artifactDirectory),
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
        let bundle = try artifactVerifier.loadEvolutionArtifacts(from: evolutionDirectory)
        return LearningCampaignAcceptedCheckpointState(
            seed: seed,
            decision: bundle.acceptedCheckpoint
        )
    }

    private func loadVectorizedBatches(from artifactDirectory: URL) throws -> [LearningCampaignVectorizedBatchState] {
        guard FileManager.default.fileExists(atPath: artifactDirectory.path) else { return [] }
        guard let enumerator = FileManager.default.enumerator(
            at: artifactDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var states: [LearningCampaignVectorizedBatchState] = []
        for case let url as URL in enumerator {
            let parentName = url.deletingLastPathComponent().lastPathComponent
            switch parentName {
            case "vectorized-evaluations":
                let artifact = try decodeIfPresent(
                    ManasMLXVectorizedEvaluationArtifact.self,
                    from: url
                )
                if let artifact {
                    states.append(LearningCampaignVectorizedBatchState(
                        kind: .evaluation,
                        seed: seedLabel(for: url, artifactRoot: artifactDirectory),
                        generationIndex: artifact.generationIndex,
                        candidateCount: artifact.requestedCandidateCount,
                        completedCandidateCount: artifact.evaluatedCandidateCount,
                        elapsedSeconds: artifact.elapsedSeconds,
                        acceleratorDevice: artifact.acceleratorDevice,
                        policyExecutionMode: artifact.policyExecutionMode,
                        observationExecutionMode: artifact.observationExecutionMode,
                        worldExecutionMode: artifact.worldExecutionMode,
                        actionEncoding: artifact.batchSpec.actionEncoding.rawValue,
                        worldActiveActionDimension: artifact.worldActiveActionDimension,
                        artifactPath: url.path,
                        bestFitness: artifact.summaries.map(\.fitness).max()
                    ))
                }
            case "vectorized-variations":
                let artifact = try decodeIfPresent(
                    ManasMLXVectorizedGenomeVariationArtifact.self,
                    from: url
                )
                if let artifact {
                    states.append(LearningCampaignVectorizedBatchState(
                        kind: .variation,
                        seed: seedLabel(for: url, artifactRoot: artifactDirectory),
                        generationIndex: artifact.generationIndex,
                        candidateCount: artifact.requestedCandidateCount,
                        completedCandidateCount: artifact.materializedCandidateCount,
                        elapsedSeconds: artifact.elapsedSeconds,
                        acceleratorDevice: artifact.acceleratorDevice,
                        policyExecutionMode: nil,
                        observationExecutionMode: nil,
                        worldExecutionMode: nil,
                        actionEncoding: nil,
                        worldActiveActionDimension: nil,
                        artifactPath: url.path,
                        bestFitness: nil
                    ))
                }
            default:
                continue
            }
        }
        return states.sorted { lhs, rhs in
            if lhs.seed != rhs.seed { return lhs.seed < rhs.seed }
            if lhs.generationIndex != rhs.generationIndex { return lhs.generationIndex < rhs.generationIndex }
            if lhs.kind != rhs.kind { return lhs.kind.rawValue < rhs.kind.rawValue }
            return lhs.artifactPath < rhs.artifactPath
        }
    }

    private func seedLabel(for url: URL, artifactRoot: URL) -> String {
        let relativePath = url.path.replacingOccurrences(of: artifactRoot.path, with: "")
        let components = relativePath.split(separator: "/").map(String.init)
        if let seedsIndex = components.firstIndex(of: "seeds"),
           components.indices.contains(seedsIndex + 1) {
            return components[seedsIndex + 1]
        }
        return "evolution"
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
