import Foundation
import KuyuTraining

struct TrainingRunStoreState: Sendable, Equatable {
    let artifactDirectory: URL
    let manifest: LearningRunManifest
    let metrics: [TrainingMetricRecord]
    let convergence: ConvergenceSummary
    let checkpointDecision: CheckpointDecision
    let lossSamples: [MetricSample]
    let validationLossSamples: [MetricSample]
    let scoreSamples: [MetricSample]
    let rewardAverageSamples: [MetricSample]
    let passRateSamples: [MetricSample]
    let failureRateSamples: [MetricSample]
    let safetyViolationSamples: [MetricSample]
    let workerThroughputSamples: [MetricSample]

    init(
        artifactDirectory: URL,
        manifest: LearningRunManifest,
        metrics: [TrainingMetricRecord],
        convergence: ConvergenceSummary,
        checkpointDecision: CheckpointDecision
    ) {
        self.artifactDirectory = artifactDirectory
        self.manifest = manifest
        self.metrics = metrics
        self.convergence = convergence
        self.checkpointDecision = checkpointDecision
        self.lossSamples = Self.samples(kind: .loss, metrics: metrics)
        self.validationLossSamples = Self.samples(kind: .validationLoss, metrics: metrics)
        self.scoreSamples = Self.samples(kind: .score, metrics: metrics)
        self.rewardAverageSamples = Self.samples(kind: .rewardAverage, metrics: metrics)
        self.passRateSamples = Self.samples(kind: .passRate, metrics: metrics)
        self.failureRateSamples = Self.samples(kind: .failureRate, metrics: metrics)
        self.safetyViolationSamples = Self.samples(kind: .safetyViolation, metrics: metrics)
        self.workerThroughputSamples = Self.samples(kind: .workerThroughput, metrics: metrics)
    }

    private static func samples(
        kind: TrainingMetricKind,
        metrics: [TrainingMetricRecord]
    ) -> [MetricSample] {
        metrics
            .filter { $0.kind == kind }
            .sorted { lhs, rhs in
                if lhs.iteration != rhs.iteration { return lhs.iteration < rhs.iteration }
                return (lhs.step ?? 0) < (rhs.step ?? 0)
            }
            .map { MetricSample(time: Double($0.step ?? $0.iteration), value: $0.value) }
    }
}

struct TrainingRunStore {
    private let artifactVerifier: GeneratedTrainingArtifactCompatibilityVerifier

    init(artifactVerifier: GeneratedTrainingArtifactCompatibilityVerifier = GeneratedTrainingArtifactCompatibilityVerifier()) {
        self.artifactVerifier = artifactVerifier
    }

    func load(from artifactDirectory: URL) throws -> TrainingRunStoreState {
        let bundle = try artifactVerifier.loadRunArtifacts(from: artifactDirectory)
        return TrainingRunStoreState(
            artifactDirectory: bundle.artifactDirectory,
            manifest: bundle.manifest,
            metrics: bundle.metrics,
            convergence: bundle.convergence,
            checkpointDecision: bundle.checkpointDecision
        )
    }
}
