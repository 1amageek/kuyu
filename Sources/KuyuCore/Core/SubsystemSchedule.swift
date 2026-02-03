public struct SubsystemSchedule: Sendable, Codable, Equatable {
    public enum ValidationError: Error, Equatable {
        case nonPositive
    }

    public let periodSteps: UInt64

    public init(periodSteps: UInt64) throws {
        guard periodSteps > 0 else { throw ValidationError.nonPositive }
        self.periodSteps = periodSteps
    }

    public func isDue(stepIndex: UInt64) -> Bool {
        stepIndex % periodSteps == 0
    }
}

