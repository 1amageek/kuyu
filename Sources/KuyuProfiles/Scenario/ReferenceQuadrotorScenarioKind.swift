import KuyuCore

public enum ReferenceQuadrotorScenarioKind: String, Sendable, Codable {
    case hoverStart
    case impulseTorqueShock
    case sustainedWindTorque
    case sensorDriftStress
    case actuatorDegradation
    case liftHover
    case singleLiftHover
}
