import KuyuPhysics

public enum KuyuSingleLiftParameterTuning {
    public static func tuned(
        parameters: ReferenceQuadrotorParameters,
        hoverThrustScale: Double
    ) throws -> ReferenceQuadrotorParameters {
        let requiredHoverThrust = parameters.mass * parameters.gravity * hoverThrustScale
        let tunedMaxThrust = max(parameters.maxThrust, requiredHoverThrust * 1.25, 12.0)
        guard tunedMaxThrust > parameters.maxThrust else {
            return parameters
        }

        return try ReferenceQuadrotorParameters(
            mass: parameters.mass,
            inertia: parameters.inertia,
            armLength: parameters.armLength,
            motorTimeConstant: parameters.motorTimeConstant,
            maxThrust: tunedMaxThrust,
            yawCoefficient: parameters.yawCoefficient,
            gravity: parameters.gravity,
            aerodynamics: parameters.aerodynamics
        )
    }
}
