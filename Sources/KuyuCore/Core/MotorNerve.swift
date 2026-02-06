public protocol MotorNerve {
    associatedtype Input
    associatedtype Output

    mutating func update(
        input: Input,
        corrections: [ReflexCorrection],
        telemetry: MotorNerveTelemetry,
        time: WorldTime
    ) throws -> Output
}

/// Final mapping stage that consumes DriveIntent and emits actuator values.
public protocol MotorNerveEndpoint: MotorNerve where Input == [DriveIntent], Output == [ActuatorValue] {}

public protocol MotorNerveTraceProvider {
    var lastTrace: MotorNerveTrace? { get }
}
