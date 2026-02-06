import KuyuCore

public final class ReferenceQuadrotorWorldStore {
    public var state: ReferenceQuadrotorState
    public var motorThrusts: MotorThrusts
    public var disturbances: DisturbanceState

    public init(
        state: ReferenceQuadrotorState,
        motorThrusts: MotorThrusts,
        disturbances: DisturbanceState = .zero
    ) {
        self.state = state
        self.motorThrusts = motorThrusts
        self.disturbances = disturbances
    }
}
