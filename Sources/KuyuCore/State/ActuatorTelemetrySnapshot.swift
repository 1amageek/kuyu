public struct ActuatorChannelSnapshot: Sendable, Codable, Equatable {
    public let id: String
    public let value: Double
    public let units: String?

    public init(id: String, value: Double, units: String? = nil) {
        self.id = id
        self.value = value
        self.units = units
    }
}

public struct ActuatorTelemetrySnapshot: Sendable, Codable, Equatable {
    public let channels: [ActuatorChannelSnapshot]

    public init(channels: [ActuatorChannelSnapshot]) {
        self.channels = channels
    }

    public func value(for id: String) -> Double? {
        channels.first(where: { $0.id == id })?.value
    }
}
