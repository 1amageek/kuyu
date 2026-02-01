public struct DriveIntent: Hashable, Sendable, Codable {
    public enum ValidationError: Error, Equatable {
        case nonFinite
    }

    public let index: DriveIndex
    public let activation: Double

    public init(index: DriveIndex, activation: Double) throws {
        guard activation.isFinite else { throw ValidationError.nonFinite }
        self.index = index
        self.activation = activation
    }
}

