import KuyuCore
import KuyuScenarios
import ManasCore

public enum ManasMLXObservationMode: Sendable, Equatable {
    case imu6
    case passThrough(channelCount: Int)

    public var channelCount: Int {
        switch self {
        case .imu6:
            return 6
        case .passThrough(let channelCount):
            return max(channelCount, 1)
        }
    }

    public static func runtimeMode(for taskMode: SimulationTaskMode) -> ManasMLXObservationMode {
        switch taskMode {
        case .lift, .singleLift:
            return .passThrough(channelCount: 8)
        case .attitude:
            return .imu6
        }
    }

    public static func trainingMode(channelCount: Int, driveCount: Int) -> ManasMLXObservationMode {
        _ = driveCount
        if channelCount > 6 {
            return .passThrough(channelCount: channelCount)
        }
        return .imu6
    }

    public static func checkpointMode(coreInputSize: Int) -> ManasMLXObservationMode {
        if coreInputSize > 24, coreInputSize % 4 == 0 {
            return .passThrough(channelCount: coreInputSize / 4)
        }
        return .imu6
    }

    public func makeBundle() -> any NerveBundle {
        switch self {
        case .imu6:
            return Imu6NerveBundle(configuration: .init(
                gyroRange: -20...20,
                accelRange: -20...20
            ))
        case .passThrough(let channelCount):
            return PassThroughNerveBundle(configuration: .init(channelCount: channelCount))
        }
    }

    public func accepts(channelIndex: UInt32) -> Bool {
        channelIndex < UInt32(channelCount)
    }
}
