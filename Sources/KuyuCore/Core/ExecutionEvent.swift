public enum ExecutionEvent: String, Sendable, Codable {
    case timeAdvance
    case disturbanceUpdate
    case actuatorUpdate
    case plantIntegrate
    case sensorSample
    case cutUpdate
    case motorNerveUpdate
    case applyCommands
    case logging
    case replayCheck
}

