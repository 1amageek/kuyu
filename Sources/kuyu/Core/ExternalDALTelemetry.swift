public struct ExternalDALTelemetry: Sendable, Codable, Equatable {
    public let motorThrusts: MotorThrusts

    public init(motorThrusts: MotorThrusts) {
        self.motorThrusts = motorThrusts
    }
}
