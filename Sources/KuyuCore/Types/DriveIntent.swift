public struct DriveIntent: Hashable, Sendable, Codable {
    public enum ValidationError: Error, Equatable {
        case nonFinite
        case nonFiniteParameter
    }

    public let index: DriveIndex
    public let activation: Double
    public let parameters: [Double]

    public var primitiveIndex: DriveIndex { index }

    public init(index: DriveIndex, activation: Double, parameters: [Double] = []) throws {
        guard activation.isFinite else { throw ValidationError.nonFinite }
        guard parameters.allSatisfy({ $0.isFinite }) else {
            throw ValidationError.nonFiniteParameter
        }
        self.index = index
        self.activation = activation
        self.parameters = parameters
    }
}
