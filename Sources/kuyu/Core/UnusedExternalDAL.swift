public struct UnusedExternalDAL: ExternalDAL {
    public enum DalError: Error, Equatable {
        case unexpectedCall
    }

    public init() {}

    public mutating func update(drives: [DriveIntent], time: WorldTime) throws -> [ActuatorCommand] {
        throw DalError.unexpectedCall
    }
}
