import Foundation
import KuyuMLXCampaignContracts
import KuyuTraining
import Observation

@Observable
@MainActor
final class LearningCampaignLiveMetrics {
    var fitnessSamples: [MetricSample] = []
    var rewardSamples: [MetricSample] = []
    var taskPassSamples: [MetricSample] = []
    var holdTimeSamples: [MetricSample] = []
    var altitudeErrorSamples: [MetricSample] = []
    var episodeSamples: [MetricSample] = []
    var candidateEvaluationCount: Int = 0
    private(set) var progressEvents: [LearningCampaignProgressEvent] = []
    private(set) var progressEventsForDisplay: [LearningCampaignProgressEvent] = []

    private var context = LearningCampaignExecutionContext(
        taskID: "unknown",
        suiteCount: 1,
        episodesPerSuite: 1
    )
    private var persistedProgressEvents: [LearningCampaignProgressEvent] = []
    private var persistedEventTimestamps: [LearningCampaignProgressEventIdentity: [Date]] = [:]
    private var liveProgressEventSet: Set<LearningCampaignProgressEvent> = []

    func updateContext(_ context: LearningCampaignExecutionContext) {
        self.context = context
    }

    func synchronizePersistedEvents(_ events: [LearningCampaignProgressEvent]) {
        var eventSet: Set<LearningCampaignProgressEvent> = []
        persistedProgressEvents = events.filter { eventSet.insert($0).inserted }
        persistedEventTimestamps = Self.eventTimestamps(for: persistedProgressEvents)
        rebuildProgressEventsForDisplay()
    }

    func reset() {
        fitnessSamples = []
        rewardSamples = []
        taskPassSamples = []
        holdTimeSamples = []
        altitudeErrorSamples = []
        episodeSamples = []
        candidateEvaluationCount = 0
        progressEvents = []
        persistedProgressEvents = []
        persistedEventTimestamps = [:]
        liveProgressEventSet = []
        progressEventsForDisplay = []
    }

    func append(_ progressEvent: TrainingRunProgressEvent) {
        append(LearningCampaignProgressEvent(progressEvent: progressEvent))
    }

    func append(_ progressRecord: LearningCampaignProgressEvent) {
        guard liveProgressEventSet.insert(progressRecord).inserted else { return }
        progressEvents.append(progressRecord)
        let maximumEntryCount = 1_000
        if progressEvents.count > maximumEntryCount {
            let removedEvents = progressEvents.prefix(progressEvents.count - maximumEntryCount)
            progressEvents.removeFirst(removedEvents.count)
            for event in removedEvents where !progressEvents.contains(event) {
                liveProgressEventSet.remove(event)
            }
        }
        if Self.containsSemanticDuplicate(
            progressRecord,
            in: persistedEventTimestamps
        ) {
            rebuildProgressEventsForDisplay()
        } else if let last = progressEventsForDisplay.last, progressRecord.timestamp < last.timestamp {
            rebuildProgressEventsForDisplay()
        } else {
            progressEventsForDisplay.append(progressRecord)
            trimProgressEventsForDisplay()
        }
        appendMetricSamples(progressRecord)
    }

    func append(_ fitness: FitnessSummary) {
        candidateEvaluationCount += 1
        let time = Double(fitness.generationIndex)
        let replacesGenerationBest = shouldReplaceGenerationBest(
            generationIndex: fitness.generationIndex,
            scalarFitness: fitness.scalarFitness
        )
        if replacesGenerationBest {
            upsert(MetricSample(time: time, value: fitness.scalarFitness), in: &fitnessSamples)
            upsert(MetricSample(time: time, value: fitness.rewardAverage), in: &rewardSamples)
            upsert(MetricSample(time: time, value: fitness.taskPassRate), in: &taskPassSamples)
            replaceOptionalSample(
                time: time,
                value: fitness.holdTimeRatio,
                in: &holdTimeSamples
            )
            replaceOptionalSample(
                time: time,
                value: fitness.altitudeErrorRatio,
                in: &altitudeErrorSamples
            )
        }
        let episodeMultiplier = max(1, context.episodesPerSuite * max(1, context.suiteCount))
        upsert(
            MetricSample(
                time: time,
                value: Double(candidateEvaluationCount * episodeMultiplier)
            ),
            in: &episodeSamples
        )
    }

    private func appendMetricSamples(_ progressRecord: LearningCampaignProgressEvent) {
        guard progressRecord.event == "candidate-evaluated",
              let generationIndex = progressRecord.generationIndex,
              let candidateID = progressRecord.candidateID,
              let fitness = progressRecord.fitness,
              let rewardAverage = progressRecord.rewardAverage else {
            return
        }
        append(FitnessSummary(
            runID: progressRecord.seed ?? "live",
            generationIndex: generationIndex,
            candidateID: candidateID,
            taskID: context.taskID,
            scalarFitness: fitness,
            rewardAverage: rewardAverage,
            taskPassRate: progressRecord.taskPassRate ?? 0,
            safetyViolationRate: progressRecord.safetyViolationRate ?? 0,
            holdTimeRatio: progressRecord.holdTimeRatio,
            altitudeErrorRatio: progressRecord.altitudeErrorRatio,
            behaviorDescriptor: [
                "evaluation.gpu": progressRecord.gpuAcceleration == true ? 1 : 0,
                "evaluation.worldTensorBatch": progressRecord.tensorWorldBatch == true ? 1 : 0,
                "evaluation.tensorSummary": progressRecord.tensorSummary == true ? 1 : 0,
                "vectorized.populationSize": Double(progressRecord.vectorizedPopulationSize ?? 0),
                "vectorized.worldCount": Double(progressRecord.vectorizedWorldCount ?? 0),
                "vectorized.historyLength": Double(progressRecord.vectorizedHistoryLength ?? 0),
                "vectorized.observationDimension": Double(progressRecord.vectorizedObservationDimension ?? 0),
                "vectorized.actionDimension": Double(progressRecord.vectorizedActionDimension ?? 0)
            ],
            failureReasons: progressRecord.failureReasons
        ))
    }

    private static let maximumDisplayedProgressEventCount = 4_000
    private static let duplicateTimestampTolerance: TimeInterval = 2

    private func rebuildProgressEventsForDisplay() {
        let persisted = persistedProgressEvents.suffix(Self.maximumDisplayedProgressEventCount)
        var eventTimestamps = Self.eventTimestamps(for: Array(persisted))
        var merged = Array(persisted)
        for event in progressEvents where !Self.containsSemanticDuplicate(event, in: eventTimestamps) {
            merged.append(event)
            eventTimestamps[LearningCampaignProgressEventIdentity(event), default: []]
                .append(event.timestamp)
        }
        merged.sort { lhs, rhs in
            lhs.timestamp < rhs.timestamp
        }
        progressEventsForDisplay = Array(merged.suffix(Self.maximumDisplayedProgressEventCount))
    }

    private static func eventTimestamps(
        for events: [LearningCampaignProgressEvent]
    ) -> [LearningCampaignProgressEventIdentity: [Date]] {
        var timestamps: [LearningCampaignProgressEventIdentity: [Date]] = [:]
        for event in events {
            timestamps[LearningCampaignProgressEventIdentity(event), default: []]
                .append(event.timestamp)
        }
        return timestamps
    }

    private static func containsSemanticDuplicate(
        _ event: LearningCampaignProgressEvent,
        in timestamps: [LearningCampaignProgressEventIdentity: [Date]]
    ) -> Bool {
        let identity = LearningCampaignProgressEventIdentity(event)
        return timestamps[identity]?.contains { timestamp in
            abs(timestamp.timeIntervalSince(event.timestamp)) <= duplicateTimestampTolerance
        } == true
    }

    private func trimProgressEventsForDisplay() {
        let slack = 512
        let overflow = progressEventsForDisplay.count - Self.maximumDisplayedProgressEventCount
        if overflow > slack {
            progressEventsForDisplay.removeFirst(overflow)
        }
    }

    private func shouldReplaceGenerationBest(generationIndex: Int, scalarFitness: Double) -> Bool {
        guard scalarFitness.isFinite else { return false }
        let time = Double(generationIndex)
        guard let existing = fitnessSamples.first(where: { $0.time == time }) else {
            return true
        }
        return scalarFitness >= existing.value
    }

    private func upsert(_ sample: MetricSample, in samples: inout [MetricSample]) {
        guard sample.value.isFinite else { return }
        if let index = samples.firstIndex(where: { $0.time == sample.time }) {
            samples[index] = sample
        } else {
            samples.append(sample)
        }
        samples.sort { $0.time < $1.time }
        let maximumSampleCount = 500
        if samples.count > maximumSampleCount {
            samples.removeFirst(samples.count - maximumSampleCount)
        }
    }

    private func replaceOptionalSample(
        time: Double,
        value: Double?,
        in samples: inout [MetricSample]
    ) {
        guard let value, value.isFinite else {
            samples.removeAll { $0.time == time }
            return
        }
        upsert(MetricSample(time: time, value: value), in: &samples)
    }
}

private struct LearningCampaignProgressEventIdentity: Hashable {
    let event: String
    let status: String?
    let exitCode: Int?
    let phase: String?
    let seed: String?
    let generationIndex: Int?
    let candidateID: String?
    let workProgress: LearningCampaignWorkProgressIdentity?
    let fitness: Double?
    let rewardAverage: Double?
    let taskPassRate: Double?
    let safetyViolationRate: Double?
    let holdTimeRatio: Double?
    let altitudeErrorRatio: Double?
    let workerThroughput: Double?
    let gpuAcceleration: Bool?
    let tensorWorldBatch: Bool?
    let tensorSummary: Bool?
    let vectorizedPopulationSize: Int?
    let vectorizedWorldCount: Int?
    let vectorizedHistoryLength: Int?
    let vectorizedObservationDimension: Int?
    let vectorizedActionDimension: Int?
    let failureReasons: [String]
    let bestCandidateID: String?
    let accepted: Bool?
    let path: String?
    let message: String?

    init(_ event: LearningCampaignProgressEvent) {
        self.event = event.event
        self.status = event.status
        self.exitCode = event.exitCode
        self.phase = event.phase
        self.seed = event.seed
        self.generationIndex = event.generationIndex
        self.candidateID = event.candidateID
        self.workProgress = event.workProgress.map(LearningCampaignWorkProgressIdentity.init)
        self.fitness = event.fitness
        self.rewardAverage = event.rewardAverage
        self.taskPassRate = event.taskPassRate
        self.safetyViolationRate = event.safetyViolationRate
        self.holdTimeRatio = event.holdTimeRatio
        self.altitudeErrorRatio = event.altitudeErrorRatio
        self.workerThroughput = event.workerThroughput
        self.gpuAcceleration = event.gpuAcceleration
        self.tensorWorldBatch = event.tensorWorldBatch
        self.tensorSummary = event.tensorSummary
        self.vectorizedPopulationSize = event.vectorizedPopulationSize
        self.vectorizedWorldCount = event.vectorizedWorldCount
        self.vectorizedHistoryLength = event.vectorizedHistoryLength
        self.vectorizedObservationDimension = event.vectorizedObservationDimension
        self.vectorizedActionDimension = event.vectorizedActionDimension
        self.failureReasons = event.failureReasons
        self.bestCandidateID = event.bestCandidateID
        self.accepted = event.accepted
        self.path = event.path
        self.message = event.message
    }
}

private struct LearningCampaignWorkProgressIdentity: Hashable {
    let scope: TrainingWorkScope
    let phase: TrainingWorkPhase
    let state: TrainingWorkState
    let unit: TrainingWorkUnit
    let completedUnitCount: Int
    let totalUnitCount: Int
    let populationSize: Int?

    init(_ progress: TrainingWorkProgress) {
        self.scope = progress.scope
        self.phase = progress.phase
        self.state = progress.state
        self.unit = progress.unit
        self.completedUnitCount = progress.completedUnitCount
        self.totalUnitCount = progress.totalUnitCount
        self.populationSize = progress.populationSize
    }
}
