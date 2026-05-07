import Foundation
import KuyuTraining

public enum KuyuRegressionQualityGatePolicy {
    public static let referenceEvaluatorID = "ReferenceQuadrotorScenarioEvaluator"
    public static let qualityEvaluatorID = "ReferenceQuadrotorTaskQualityEvaluator"

    public static func defaultMinimumRewardAverage(for task: String) -> Double? {
        do {
            return try TaskEvaluationProfile.profile(task: task).minimumRewardAverage
        } catch {
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
        let profile: TaskEvaluationProfile?
        do {
            profile = try TaskEvaluationProfile.profile(task: task)
        } catch {
            profile = nil
        }
        return KuyuRegressionQualityRequirement(
            task: task,
            evaluatorID: profile?.referenceEvaluatorID ?? referenceEvaluatorID,
            qualityEvaluatorID: profile?.qualityEvaluatorID ?? qualityEvaluatorID,
            requiresReferenceTaskPass: profile?.requiresReferenceTaskPass ?? true,
            minimumTaskPassRate: profile?.minimumTaskPassRate ?? 1.0,
            minimumRewardAverage: minimumRewardAverage,
            minimumHoldTimeRatio: profile?.minimumHoldTimeRatio ?? 1.0,
            maximumAltitudeErrorRatio: profile?.maximumAltitudeErrorRatio,
            liftThresholdSource: profile?.liftThresholdSource ?? liftThresholdSource(for: task)
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
