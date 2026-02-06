import KuyuCore

public struct AerodynamicsParameters: Sendable, Equatable, Codable {
    public enum ValidationError: Error, Equatable {
        case nonFinite(String)
        case negative(String)
    }

    public let dragCoefficient: Double
    public let referenceArea: Double
    public let liftCoefficient: Double
    public let bodyVolume: Double
    public let angularDrag: Axis3

    public init(
        dragCoefficient: Double,
        referenceArea: Double,
        liftCoefficient: Double,
        bodyVolume: Double,
        angularDrag: Axis3
    ) throws {
        guard dragCoefficient.isFinite else { throw ValidationError.nonFinite("dragCoefficient") }
        guard referenceArea.isFinite else { throw ValidationError.nonFinite("referenceArea") }
        guard liftCoefficient.isFinite else { throw ValidationError.nonFinite("liftCoefficient") }
        guard bodyVolume.isFinite else { throw ValidationError.nonFinite("bodyVolume") }
        guard angularDrag.x.isFinite,
              angularDrag.y.isFinite,
              angularDrag.z.isFinite else {
            throw ValidationError.nonFinite("angularDrag")
        }

        guard dragCoefficient >= 0 else { throw ValidationError.negative("dragCoefficient") }
        guard referenceArea >= 0 else { throw ValidationError.negative("referenceArea") }
        guard liftCoefficient >= 0 else { throw ValidationError.negative("liftCoefficient") }
        guard bodyVolume >= 0 else { throw ValidationError.negative("bodyVolume") }
        guard angularDrag.x >= 0,
              angularDrag.y >= 0,
              angularDrag.z >= 0 else {
            throw ValidationError.negative("angularDrag")
        }

        self.dragCoefficient = dragCoefficient
        self.referenceArea = referenceArea
        self.liftCoefficient = liftCoefficient
        self.bodyVolume = bodyVolume
        self.angularDrag = angularDrag
    }

    public static let zero: AerodynamicsParameters = {
        do {
            return try AerodynamicsParameters(
                dragCoefficient: 0,
                referenceArea: 0,
                liftCoefficient: 0,
                bodyVolume: 0,
                angularDrag: Axis3(x: 0, y: 0, z: 0)
            )
        } catch {
            preconditionFailure("Invalid zero aerodynamics parameters: \(error)")
        }
    }()

    public static let baseline: AerodynamicsParameters = {
        do {
            return try AerodynamicsParameters(
                dragCoefficient: 1.1,
                referenceArea: 0.05,
                liftCoefficient: 0.2,
                bodyVolume: 0.003,
                angularDrag: Axis3(x: 0.02, y: 0.02, z: 0.04)
            )
        } catch {
            preconditionFailure("Invalid baseline aerodynamics parameters: \(error)")
        }
    }()
}
