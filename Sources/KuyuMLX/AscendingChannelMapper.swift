import KuyuCore
import KuyuPhysics

/// Maps FusedState to Manas ascending channel arrays by type.
///
/// Ascending channel types:
/// - Type S: Raw sensor channels (ChannelSample values)
/// - Type P: Physics prediction channels (from AnalyticalState)
/// - Type R: Residual channels (from WorldModel corrections)
/// - Type E: Extension channels (from WorldModel extensions)
public struct AscendingChannelMapper {
    public enum ChannelType: Int, Sendable {
        case sensor = 0
        case physics = 1
        case residual = 2
        case extensionChannel = 3
    }

    public struct AscendingChannels: Sendable {
        /// Type S: Raw sensor values (from ChannelSample)
        public let sensor: [Float]
        /// Type P: Physics prediction (from AnalyticalState.toArray())
        public let physics: [Float]
        /// Type R: Residual corrections (from WorldModelOutput.residual)
        public let residual: [Float]
        /// Type E: Extension dimensions (from WorldModelOutput.extensions)
        public let extensions: [Float]

        /// All channels concatenated: [S..., P..., R..., E...]
        public var concatenated: [Float] {
            sensor + physics + residual + extensions
        }

        /// Type indices for each channel in the concatenated array.
        /// Used for Manas type embeddings.
        public var typeIndices: [Int] {
            Array(repeating: ChannelType.sensor.rawValue, count: sensor.count)
            + Array(repeating: ChannelType.physics.rawValue, count: physics.count)
            + Array(repeating: ChannelType.residual.rawValue, count: residual.count)
            + Array(repeating: ChannelType.extensionChannel.rawValue, count: extensions.count)
        }

        /// Total number of ascending channels.
        public var totalCount: Int {
            sensor.count + physics.count + residual.count + extensions.count
        }
    }

    public init() {}

    /// Map a FusedState and sensor samples to ascending channels.
    public func map<S: AnalyticalState>(
        fusedState: FusedState<S>,
        sensorSamples: [ChannelSample]
    ) -> AscendingChannels {
        let sensorValues = sensorSamples.map { Float($0.value) }
        let physicsValues = fusedState.physics.toArray()

        return AscendingChannels(
            sensor: sensorValues,
            physics: physicsValues,
            residual: fusedState.worldModelOutput.residual,
            extensions: fusedState.worldModelOutput.extensions
        )
    }

    /// Map physics-only state (no world model) to ascending channels.
    /// Equivalent to using IdentityWorldModel (residual=0, extensions=empty).
    public func mapPhysicsOnly<S: AnalyticalState>(
        physicsState: S,
        sensorSamples: [ChannelSample]
    ) -> AscendingChannels {
        let sensorValues = sensorSamples.map { Float($0.value) }
        let physicsValues = physicsState.toArray()

        return AscendingChannels(
            sensor: sensorValues,
            physics: physicsValues,
            residual: Array(repeating: Float(0), count: physicsValues.count),
            extensions: []
        )
    }
}
