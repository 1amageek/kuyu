import KuyuCore

public enum SwapEvent: Sendable, Codable, Equatable {
    case sensor(SensorSwapEvent)
    case actuator(ActuatorSwapEvent)
}
