import KuyuCore

public struct MotorThrusts: Sendable, Codable, Equatable {
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

    public static let zero: MotorThrusts = {
        do {
            return try MotorThrusts(f1: 0, f2: 0, f3: 0, f4: 0)
        } catch {
            preconditionFailure("Invalid zero thrusts: \(error)")
        }
    }()

    public static func uniform(_ value: Double) throws -> MotorThrusts {
        try MotorThrusts(f1: value, f2: value, f3: value, f4: value)
    }

    public func asArray() -> [Double] {
        [f1, f2, f3, f4]
    }
}
