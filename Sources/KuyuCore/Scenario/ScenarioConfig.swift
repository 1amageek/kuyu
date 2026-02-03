import Foundation

public struct ScenarioConfig: Sendable, Codable, Equatable {
    public enum ValidationError: Error, Equatable {
        case nonFinite(String)
        case nonPositive(String)
    }

    public let id: ScenarioID
    public let seed: ScenarioSeed
    public let duration: TimeInterval
    public let timeStep: TimeStep

    public init(
        id: ScenarioID,
        seed: ScenarioSeed,
        duration: TimeInterval,
        timeStep: TimeStep
    ) throws {
        guard duration.isFinite else { throw ValidationError.nonFinite("duration") }
        guard duration > 0 else { throw ValidationError.nonPositive("duration") }

        self.id = id
        self.seed = seed
        self.duration = duration
        self.timeStep = timeStep
    }
}

