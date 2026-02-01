public enum ScenarioKind: String, Sendable, Codable {
    case hoverStart
    case impulseTorqueShock
    case sustainedWindTorque
    case sensorDriftStress
    case actuatorDegradation
}
