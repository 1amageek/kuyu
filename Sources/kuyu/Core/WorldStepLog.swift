import Foundation

public struct WorldStepLog: Sendable, Codable, Equatable {
    public let time: WorldTime
    public let events: [ExecutionEvent]
    public let sensorSamples: [ChannelSample]
    public let actuatorCommands: [ActuatorCommand]
    public let motorThrusts: MotorThrusts
    public let safetyTrace: SafetyTrace
    public let stateSnapshot: QuadrotorStateSnapshot
    public let disturbanceTorqueBody: Axis3
    public let disturbanceForceWorld: Axis3

    public init(
        time: WorldTime,
        events: [ExecutionEvent],
        sensorSamples: [ChannelSample],
        actuatorCommands: [ActuatorCommand],
        motorThrusts: MotorThrusts,
        safetyTrace: SafetyTrace,
        stateSnapshot: QuadrotorStateSnapshot,
        disturbanceTorqueBody: Axis3,
        disturbanceForceWorld: Axis3
    ) {
        self.time = time
        self.events = events
        self.sensorSamples = sensorSamples
        self.actuatorCommands = actuatorCommands
        self.motorThrusts = motorThrusts
        self.safetyTrace = safetyTrace
        self.stateSnapshot = stateSnapshot
        self.disturbanceTorqueBody = disturbanceTorqueBody
        self.disturbanceForceWorld = disturbanceForceWorld
    }
}
