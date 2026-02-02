public struct WorldEnvironment: Sendable, Codable, Equatable {
    public enum ValidationError: Error, Equatable {
        case nonFinite(String)
        case nonPositive(String)
    }

    public let gravity: Double
    public let windVelocityWorld: Axis3
    public let airPressure: Double
    public let airTemperature: Double
    public let usage: WorldEnvironmentUsage

    public init(
        gravity: Double,
        windVelocityWorld: Axis3,
        airPressure: Double,
        airTemperature: Double,
        usage: WorldEnvironmentUsage = .none
    ) throws {
        guard gravity.isFinite else { throw ValidationError.nonFinite("gravity") }
        guard airPressure.isFinite else { throw ValidationError.nonFinite("airPressure") }
        guard airTemperature.isFinite else { throw ValidationError.nonFinite("airTemperature") }
        guard windVelocityWorld.x.isFinite,
              windVelocityWorld.y.isFinite,
              windVelocityWorld.z.isFinite else {
            throw ValidationError.nonFinite("windVelocityWorld")
        }

        guard gravity > 0 else { throw ValidationError.nonPositive("gravity") }
        guard airPressure > 0 else { throw ValidationError.nonPositive("airPressure") }
        guard airTemperature > 0 else { throw ValidationError.nonPositive("airTemperature") }

        self.gravity = gravity
        self.windVelocityWorld = windVelocityWorld
        self.airPressure = airPressure
        self.airTemperature = airTemperature
        self.usage = usage
    }

    public static let standard: WorldEnvironment = {
        do {
            return try WorldEnvironment(
                gravity: 9.80665,
                windVelocityWorld: Axis3(x: 0, y: 0, z: 0),
                airPressure: 101_325.0,
                airTemperature: 288.15,
                usage: .none
            )
        } catch {
            preconditionFailure("Invalid standard world environment: \(error)")
        }
    }()

    public static let dryAirGasConstant = 287.05
    public static let seaLevelDensity: Double = {
        let pressure = 101_325.0
        let temperature = 288.15
        return pressure / (dryAirGasConstant * temperature)
    }()

    public func effectiveGravity(defaultGravity: Double) -> Double {
        usage.useGravity ? gravity : defaultGravity
    }

    public func airDensity() -> Double {
        airPressure / (Self.dryAirGasConstant * airTemperature)
    }
}
