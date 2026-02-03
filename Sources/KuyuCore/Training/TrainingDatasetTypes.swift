import Foundation

public struct TrainingDatasetMetadata: Sendable, Codable, Equatable {
    public let version: String
    public let scenarioId: String
    public let seed: UInt64
    public let timeStep: Double
    public let determinismTier: String
    public let configHash: String
    public let channelCount: Int
    public let driveCount: Int
    public let recordCount: Int

    public init(
        version: String,
        scenarioId: String,
        seed: UInt64,
        timeStep: Double,
        determinismTier: String,
        configHash: String,
        channelCount: Int,
        driveCount: Int,
        recordCount: Int
    ) {
        self.version = version
        self.scenarioId = scenarioId
        self.seed = seed
        self.timeStep = timeStep
        self.determinismTier = determinismTier
        self.configHash = configHash
        self.channelCount = channelCount
        self.driveCount = driveCount
        self.recordCount = recordCount
    }
}

public struct TrainingSensorSample: Sendable, Codable, Equatable {
    public let channelIndex: UInt32
    public let value: Double
    public let timestamp: Double

    public init(channelIndex: UInt32, value: Double, timestamp: Double) {
        self.channelIndex = channelIndex
        self.value = value
        self.timestamp = timestamp
    }
}

public struct TrainingDriveIntent: Sendable, Codable, Equatable {
    public let driveIndex: UInt32
    public let value: Double

    public init(driveIndex: UInt32, value: Double) {
        self.driveIndex = driveIndex
        self.value = value
    }
}

public struct TrainingReflexCorrection: Sendable, Codable, Equatable {
    public let driveIndex: UInt32
    public let clamp: Double
    public let damping: Double
    public let delta: Double

    public init(driveIndex: UInt32, clamp: Double, damping: Double, delta: Double) {
        self.driveIndex = driveIndex
        self.clamp = clamp
        self.damping = damping
        self.delta = delta
    }
}

public struct TrainingDatasetRecord: Sendable, Codable, Equatable {
    public let time: Double
    public let sensors: [TrainingSensorSample]
    public let driveIntents: [TrainingDriveIntent]
    public let reflexCorrections: [TrainingReflexCorrection]

    public init(
        time: Double,
        sensors: [TrainingSensorSample],
        driveIntents: [TrainingDriveIntent],
        reflexCorrections: [TrainingReflexCorrection]
    ) {
        self.time = time
        self.sensors = sensors
        self.driveIntents = driveIntents
        self.reflexCorrections = reflexCorrections
    }
}
