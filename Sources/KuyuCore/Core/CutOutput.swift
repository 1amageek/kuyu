public enum CutOutput: Sendable, Codable, Equatable {
    case actuatorCommands([ActuatorCommand])
    case driveIntents([DriveIntent], corrections: [ReflexCorrection])
}
