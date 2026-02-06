import KuyuCore

public struct MotorMaxThrusts: Sendable, Codable, Equatable {
    public enum ValidationError: Error, Equatable {
        case nonFinite(String)
        case negative(String)
    }

    public let f1: Double
    public let f2: Double
    public let f3: Double
    public let f4: Double

    public init(f1: Double, f2: Double, f3: Double, f4: Double) throws {
        guard f1.isFinite else { throw ValidationError.nonFinite("f1") }
        guard f2.isFinite else { throw ValidationError.nonFinite("f2") }
        guard f3.isFinite else { throw ValidationError.nonFinite("f3") }
        guard f4.isFinite else { throw ValidationError.nonFinite("f4") }

        guard f1 >= 0 else { throw ValidationError.negative("f1") }
        guard f2 >= 0 else { throw ValidationError.negative("f2") }
        guard f3 >= 0 else { throw ValidationError.negative("f3") }
        guard f4 >= 0 else { throw ValidationError.negative("f4") }

        self.f1 = f1
        self.f2 = f2
        self.f3 = f3
        self.f4 = f4
    }

    public static func uniform(_ value: Double) throws -> MotorMaxThrusts {
        try MotorMaxThrusts(f1: value, f2: value, f3: value, f4: value)
    }

    public func max(forIndex index: UInt32) -> Double {
        switch index {
        case 0: return f1
        case 1: return f2
        case 2: return f3
        case 3: return f4
        default: return 0
        }
    }

    public func setting(index: UInt32, value: Double) throws -> MotorMaxThrusts {
        switch index {
        case 0:
            return try MotorMaxThrusts(f1: value, f2: f2, f3: f3, f4: f4)
        case 1:
            return try MotorMaxThrusts(f1: f1, f2: value, f3: f3, f4: f4)
        case 2:
            return try MotorMaxThrusts(f1: f1, f2: f2, f3: value, f4: f4)
        case 3:
            return try MotorMaxThrusts(f1: f1, f2: f2, f3: f3, f4: value)
        default:
            return self
        }
    }
}
