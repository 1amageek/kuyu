import KuyuCore

/// Controls difficulty progression during curriculum learning.
///
/// Tracks the current difficulty level and advances when the controller
/// achieves sufficient pass rate at the current level. Inspired by
/// Micro-World's progressive training approach.
public struct CurriculumController {

    public struct Config: Sendable, Equatable {
        public let totalLevels: Int
        public let scenariosPerLevel: Int
        public let advanceThreshold: Double
        public let maxEpochsPerLevel: Int

        public init(
            totalLevels: Int = 5,
            scenariosPerLevel: Int = 20,
            advanceThreshold: Double = 0.8,
            maxEpochsPerLevel: Int = 10
        ) {
            self.totalLevels = totalLevels
            self.scenariosPerLevel = scenariosPerLevel
            self.advanceThreshold = advanceThreshold
            self.maxEpochsPerLevel = maxEpochsPerLevel
        }
    }

    public enum AdvanceResult: Sendable, Equatable {
        case advanced(newLevel: Int)
        case stayAtLevel(currentLevel: Int, passRate: Double)
        case completed
        case maxEpochsReached(level: Int)
    }

    public let config: Config
    public private(set) var currentLevel: Int
    public private(set) var epochsAtCurrentLevel: Int
    public private(set) var levelHistory: [LevelRecord]

    public struct LevelRecord: Sendable, Equatable {
        public let level: Int
        public let epochsSpent: Int
        public let finalPassRate: Double
    }

    public init(config: Config = Config()) {
        self.config = config
        self.currentLevel = 0
        self.epochsAtCurrentLevel = 0
        self.levelHistory = []
    }

    /// Report evaluation results for the current level and determine advancement.
    public mutating func report(evaluations: [ExtendedScenarioEvaluation]) -> AdvanceResult {
        guard currentLevel < config.totalLevels else {
            return .completed
        }

        epochsAtCurrentLevel += 1

        let passCount = evaluations.filter(\.base.passed).count
        let passRate = evaluations.isEmpty ? 0 : Double(passCount) / Double(evaluations.count)

        if passRate >= config.advanceThreshold {
            let record = LevelRecord(
                level: currentLevel,
                epochsSpent: epochsAtCurrentLevel,
                finalPassRate: passRate
            )
            levelHistory.append(record)

            currentLevel += 1
            epochsAtCurrentLevel = 0

            if currentLevel >= config.totalLevels {
                return .completed
            }
            return .advanced(newLevel: currentLevel)
        }

        if epochsAtCurrentLevel >= config.maxEpochsPerLevel {
            let record = LevelRecord(
                level: currentLevel,
                epochsSpent: epochsAtCurrentLevel,
                finalPassRate: passRate
            )
            levelHistory.append(record)

            currentLevel += 1
            epochsAtCurrentLevel = 0

            if currentLevel >= config.totalLevels {
                return .completed
            }
            return .maxEpochsReached(level: currentLevel - 1)
        }

        return .stayAtLevel(currentLevel: currentLevel, passRate: passRate)
    }

    /// Whether all levels have been completed.
    public var isComplete: Bool {
        currentLevel >= config.totalLevels
    }

    /// Fraction of the curriculum completed (0.0 to 1.0).
    public var progress: Double {
        Double(currentLevel) / Double(config.totalLevels)
    }
}
