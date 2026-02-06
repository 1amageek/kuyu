public enum CutOutput: Sendable, Codable, Equatable {
    case actuatorValues([ActuatorValue])
    case driveIntents([DriveIntent], corrections: [ReflexCorrection])
}
