import Foundation
import KuyuTraining
import Testing
@testable import KuyuUI

@Suite("Learning progress snapshot")
struct LearningProgressSnapshotTests {
    @Test func separatesAttemptsFromRetainedGenerations() {
        let records = [
            makeRecord(
                iteration: 0,
                supportHorizon: 100,
                accepted: false,
                failureRate: 0.2,
                failureSeed: 1
            ),
            makeRecord(
                iteration: 1,
                supportHorizon: 120,
                accepted: true,
                failureRate: 0.1,
                checkpointPath: "checkpoints/generation-1"
            ),
            makeRecord(
                iteration: 2,
                supportHorizon: 160,
                accepted: false,
                failureRate: 0.25,
                failureSeed: 2,
                policyPassed: false
            ),
            makeRecord(
                iteration: 3,
                supportHorizon: 180,
                accepted: true,
                failureRate: 0,
                checkpointPath: "checkpoints/generation-2"
            ),
            makeRecord(
                iteration: 4,
                supportHorizon: 200,
                accepted: false,
                failureRate: 0,
                policyPassed: true
            ),
        ]

        let snapshot = LearningProgressSnapshot(records: records)

        #expect(snapshot.attempts.count == 5)
        #expect(snapshot.acceptedGenerationCount == 2)
        #expect(snapshot.decisionRecordedCount == 5)
        #expect(snapshot.hasGenerationLineage)
        #expect(snapshot.currentGeneration == 2)
        #expect(snapshot.attemptsSinceLastAccepted == 1)
        #expect(snapshot.generations.map(\.id) == [0, 1, 2])

        let baseline = snapshot.generations[0]
        #expect(baseline.acceptedAtAttempt == nil)
        #expect(baseline.firstAttempt == 1)
        #expect(baseline.lastAttempt == 1)

        let firstGeneration = snapshot.generations[1]
        #expect(firstGeneration.acceptedAtAttempt == 2)
        #expect(firstGeneration.firstAttempt == 2)
        #expect(firstGeneration.lastAttempt == 3)
        #expect(firstGeneration.bestSupportHorizon == 160)
        #expect(firstGeneration.latestEvaluationPassed == false)
        #expect(firstGeneration.checkpointPath == "checkpoints/generation-1")

        let currentGeneration = snapshot.generations[2]
        #expect(currentGeneration.acceptedAtAttempt == 4)
        #expect(currentGeneration.lastAttempt == 5)
        #expect(currentGeneration.latestEvaluationPassed == true)
        #expect(snapshot.supportCompletionRatio == 1)
        #expect(snapshot.latestEvaluationAttempt == 5)
        #expect(snapshot.latestEvaluationPassed == true)
    }

    @Test func groupsFailureObservationsWithoutDiscardingDuplicates() {
        let records = [
            makeRecord(
                iteration: 0,
                supportHorizon: 100,
                accepted: false,
                failureRate: 0.5,
                failureSeed: 7,
                duplicateFailure: true
            ),
            makeRecord(
                iteration: 1,
                supportHorizon: 100,
                accepted: false,
                failureRate: 0.5,
                failureSeed: 8
            ),
        ]

        let snapshot = LearningProgressSnapshot(records: records)

        #expect(snapshot.failureObservations.count == 3)
        #expect(snapshot.failureGroups.count == 1)
        let group = snapshot.failureGroups[0]
        #expect(group.scenario == "scenario-a")
        #expect(group.reason == "sustained-fall")
        #expect(group.observationCount == 3)
        #expect(group.seeds == [7, 8])
        #expect(group.firstAttempt == 1)
        #expect(group.lastAttempt == 2)
        #expect(snapshot.failureGroups(forRevision: 0).first?.observationCount == 3)
        #expect(snapshot.failureGroups(forRevision: 1).isEmpty)
    }

    @Test func emptyJournalProducesAnEmptyOverview() {
        let snapshot = LearningProgressSnapshot(records: [])

        #expect(snapshot.attempts.isEmpty)
        #expect(snapshot.generations.isEmpty)
        #expect(snapshot.failureGroups.isEmpty)
        #expect(snapshot.acceptedGenerationCount == 0)
        #expect(snapshot.decisionRecordedCount == 0)
        #expect(!snapshot.hasGenerationLineage)
        #expect(snapshot.supportCompletionRatio == nil)
        #expect(snapshot.latestEvaluationPassed == nil)
    }

    @Test func mapsTrainingRunMetricsToLearningSignals() throws {
        let record = TrainingRunIterationRecord(
            iteration: 0,
            recordedAt: Date(timeIntervalSince1970: 0),
            evaluation: TrainingRunIterationRecord.EvaluationRecord(
                evaluationHorizon: 0,
                metrics: [
                    "score": 0.73,
                    "suitePassed": 1,
                    "trainingLoss": 0.42,
                ]
            )
        )

        let snapshot = LearningProgressSnapshot(records: [record])
        let attempt = try #require(snapshot.attempts.first)

        #expect(attempt.evaluationScore == 0.73)
        #expect(attempt.evaluationPassed == true)
        #expect(attempt.trainingLoss == 0.42)
        #expect(snapshot.latestEvaluationScore == 0.73)
        #expect(snapshot.latestEvaluationPassed == true)
    }

    @Test func keepsScoreVisibleWhenEvaluationGateIsMissing() throws {
        let record = TrainingRunIterationRecord(
            iteration: 0,
            recordedAt: Date(timeIntervalSince1970: 0),
            evaluation: TrainingRunIterationRecord.EvaluationRecord(
                evaluationHorizon: 0,
                metrics: ["score": 0.61]
            )
        )

        let snapshot = LearningProgressSnapshot(records: [record])

        #expect(snapshot.latestEvaluationAttempt == 1)
        #expect(snapshot.latestEvaluationScore == 0.61)
        #expect(snapshot.latestEvaluationPassed == nil)
        #expect(!snapshot.hasGenerationLineage)
    }

    private func makeRecord(
        iteration: Int,
        supportHorizon: Int,
        accepted: Bool,
        failureRate: Double,
        failureSeed: UInt64? = nil,
        duplicateFailure: Bool = false,
        checkpointPath: String? = nil,
        policyPassed: Bool? = nil
    ) -> TrainingRunIterationRecord {
        let failureEpisodes: [TrainingRunIterationRecord.FailureEpisode]
        if let failureSeed {
            let failure = TrainingRunIterationRecord.FailureEpisode(
                scenario: "scenario-a",
                seed: failureSeed,
                terminalStep: 80 + iteration,
                reason: "sustained-fall"
            )
            failureEpisodes = duplicateFailure ? [failure, failure] : [failure]
        } else {
            failureEpisodes = []
        }

        let evaluation = policyPassed.map {
            TrainingRunIterationRecord.EvaluationRecord(
                evaluationHorizon: supportHorizon,
                metrics: [
                    "policyPassed": $0 ? 1 : 0,
                    "policyScore": $0 ? 1 : 0,
                ]
            )
        }
        let checkpoint = checkpointPath.map {
            TrainingRunIterationRecord.CheckpointReference(
                path: $0,
                sha256Digest: String(repeating: "a", count: 64)
            )
        }

        return TrainingRunIterationRecord(
            iteration: iteration,
            recordedAt: Date(timeIntervalSince1970: Double(iteration)),
            horizon: TrainingRunIterationRecord.HorizonState(
                supportHorizon: supportHorizon,
                frontierHorizon: supportHorizon,
                fullHorizon: 200,
                mode: "ppo"
            ),
            decision: TrainingRunIterationRecord.CandidateDecision(
                accepted: accepted,
                materiallyImproved: accepted,
                rejectionReasons: accepted ? [] : ["regressed"],
                progressSignals: accepted ? ["reward-average-improved"] : [],
                progressRejectionReasons: accepted ? [] : ["candidate-not-retained"],
                horizonHealth: [
                    "episodeCount": 2,
                    "failureCount": failureRate * 2,
                    "failureRate": failureRate,
                    "maxOmega": 2 + Double(iteration),
                    "rewardAverage": -50,
                    "terminalStepAverage": 100,
                ]
            ),
            evaluation: evaluation,
            failureEpisodes: failureEpisodes,
            phaseTimings: ["iterationSeconds": 1],
            checkpoint: checkpoint
        )
    }
}
