public protocol ExternalDAL: Sendable {
    mutating func update(drives: [DriveIntent], time: WorldTime) throws -> [ActuatorCommand]
}

