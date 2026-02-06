/// Identifier for a motor primitive in the body/MotorNerve descriptor.
public struct DriveIndex: Hashable, Sendable, Codable {
    public let rawValue: UInt32

    public init(_ rawValue: UInt32) {
        self.rawValue = rawValue
    }
}
