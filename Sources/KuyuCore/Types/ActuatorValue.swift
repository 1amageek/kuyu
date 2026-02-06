public struct ActuatorValue: Hashable, Sendable, Codable {
    public enum ValidationError: Error, Equatable {
        case nonFinite
    }

    public let index: ActuatorIndex
    public let value: Double

    public init(index: ActuatorIndex, value: Double) throws {
        guard value.isFinite else { throw ValidationError.nonFinite }
        self.index = index
        self.value = value
    }
}

