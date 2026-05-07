import Foundation
import KuyuTraining

public struct LearningCampaignAdaptiveMutationPlan: Codable, Sendable, Equatable {
    public let enabled: Bool
    public let increaseFactor: Double
    public let decayFactor: Double
    public let minimumMutationRate: Double
    public let maximumMutationRate: Double
    public let minimumNoiseScale: Double
    public let maximumNoiseScale: Double

    public init(
        enabled: Bool = false,
        increaseFactor: Double = 1.25,
        decayFactor: Double = 0.9,
        minimumMutationRate: Double = 0,
        maximumMutationRate: Double = 0.5,
        minimumNoiseScale: Double = 0,
        maximumNoiseScale: Double = 0.1
    ) {
        self.enabled = enabled
        self.increaseFactor = max(1, increaseFactor)
        self.decayFactor = min(1, max(0, decayFactor))
        self.minimumMutationRate = max(0, minimumMutationRate)
        self.maximumMutationRate = max(self.minimumMutationRate, maximumMutationRate)
        self.minimumNoiseScale = max(0, minimumNoiseScale)
        self.maximumNoiseScale = max(self.minimumNoiseScale, maximumNoiseScale)
    }

    public var evolutionConfig: EvolutionAdaptiveMutationConfig {
        EvolutionAdaptiveMutationConfig(
            enabled: enabled,
            increaseFactor: increaseFactor,
            decayFactor: decayFactor,
            minimumMutationRate: minimumMutationRate,
            maximumMutationRate: maximumMutationRate,
            minimumNoiseScale: minimumNoiseScale,
            maximumNoiseScale: maximumNoiseScale
        )
    }
}
