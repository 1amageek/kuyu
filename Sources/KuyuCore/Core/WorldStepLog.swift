import Foundation

public struct WorldStepLog: Sendable, Codable, Equatable {
    public let time: WorldTime
    public let events: [ExecutionEvent]
    public let sensorSamples: [ChannelSample]
    public let driveIntents: [DriveIntent]
    public let reflexCorrections: [ReflexCorrection]
    public let actuatorValues: [ActuatorValue]
    public let actuatorTelemetry: ActuatorTelemetrySnapshot
    public let motorNerveTrace: MotorNerveTrace?
    public let safetyTrace: SafetyTrace
    public let plantState: PlantStateSnapshot
    public let disturbances: DisturbanceSnapshot

    public init(
        time: WorldTime,
        events: [ExecutionEvent],
        sensorSamples: [ChannelSample],
        driveIntents: [DriveIntent],
        reflexCorrections: [ReflexCorrection],
        actuatorValues: [ActuatorValue],
        actuatorTelemetry: ActuatorTelemetrySnapshot,
        motorNerveTrace: MotorNerveTrace? = nil,
        safetyTrace: SafetyTrace,
        plantState: PlantStateSnapshot,
        disturbances: DisturbanceSnapshot
    ) {
        self.time = time
        self.events = events
        self.sensorSamples = sensorSamples
        self.driveIntents = driveIntents
        self.reflexCorrections = reflexCorrections
        self.actuatorValues = actuatorValues
        self.actuatorTelemetry = actuatorTelemetry
        self.motorNerveTrace = motorNerveTrace
        self.safetyTrace = safetyTrace
        self.plantState = plantState
        self.disturbances = disturbances
    }
}
