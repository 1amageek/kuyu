import Foundation
import KuyuTraining

struct TrainingRunTestMatrixSnapshot: Sendable, Equatable {
    struct TestCase: Identifiable, Sendable, Equatable {
        let scenarioID: String
        let seed: UInt64
        let passed: Bool
        let failureReasons: [String]
        let durationSeconds: Double?
        let timeStepSeconds: Double?
        let stepCount: Int?

        var id: String {
            "\(scenarioID)#\(seed)"
        }
    }

    let evaluationID: String
    let evaluatedAt: Date
    let task: String
    let profileID: String
    let checkpointPath: String
    let policyPassed: Bool
    let policyScore: Double
    let scenarioIDs: [String]
    let seeds: [UInt64]
    let testCases: [TestCase]
    let passedCount: Int
    let failedCount: Int

    init(artifact: CheckpointEvaluationArtifact) {
        let horizons = (artifact.scenarioHorizons ?? []).reduce(
            into: [CheckpointEvaluationScenarioKey: CheckpointEvaluationScenarioHorizon]()
        ) { result, horizon in
            result[horizon.key] = horizon
        }
        let testCases = artifact.qualitySummary.map { summary in
            let key = CheckpointEvaluationScenarioKey(qualitySummary: summary)
            let horizon = horizons[key]
            return TestCase(
                scenarioID: summary.scenarioID,
                seed: summary.seed,
                passed: summary.passed,
                failureReasons: summary.failureReasons,
                durationSeconds: horizon?.durationSeconds,
                timeStepSeconds: horizon?.timeStepSeconds,
                stepCount: horizon?.stepCount
            )
        }
        .sorted {
            if $0.scenarioID != $1.scenarioID { return $0.scenarioID < $1.scenarioID }
            return $0.seed < $1.seed
        }

        self.evaluationID = artifact.evaluationID
        self.evaluatedAt = artifact.startedAt
        self.task = artifact.task
        self.profileID = artifact.profileID
        self.checkpointPath = artifact.checkpointPath
        self.policyPassed = artifact.policyPassed
        self.policyScore = artifact.policyScore
        self.scenarioIDs = Array(Set(testCases.map(\.scenarioID))).sorted()
        self.seeds = Array(Set(testCases.map(\.seed))).sorted()
        self.testCases = testCases
        self.passedCount = testCases.filter(\.passed).count
        self.failedCount = testCases.count - passedCount
    }

    func testCase(scenarioID: String, seed: UInt64) -> TestCase? {
        testCases.first {
            $0.scenarioID == scenarioID && $0.seed == seed
        }
    }
}
