import Foundation

public enum KuyuRegressionQualityGatePolicy {
    public static let referenceEvaluatorID = "ReferenceQuadrotorScenarioEvaluator"

    public static func defaultMinimumRewardAverage(for task: String) -> Double? {
        switch task {
        case "lift", "singleLift":
            return 0
        default:
            return nil
        }
    }

    public static func minimumRewardAverage(
        override: Double?,
        task: String
    ) -> Double? {
        override ?? defaultMinimumRewardAverage(for: task)
    }

    public static func requirement(
        task: String,
        minimumRewardAverage: Double?
    ) -> KuyuRegressionQualityRequirement {
        KuyuRegressionQualityRequirement(
            task: task,
            evaluatorID: referenceEvaluatorID,
            requiresReferenceTaskPass: true,
            minimumTaskPassRate: 1.0,
            minimumRewardAverage: minimumRewardAverage,
            liftThresholdSource: liftThresholdSource(for: task)
        )
    }

    private static func liftThresholdSource(for task: String) -> String? {
        switch task {
        case "lift", "singleLift":
            return "scenario.liftEnvelope"
        default:
            return nil
        }
    }
}
