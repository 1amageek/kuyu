public final class WorldStore {
    public var state: QuadrotorState
    public var motorThrusts: MotorThrusts
    public var disturbances: DisturbanceState

    public init(
        state: QuadrotorState,
        motorThrusts: MotorThrusts,
        disturbances: DisturbanceState = .zero
    ) {
        self.state = state
        self.motorThrusts = motorThrusts
        self.disturbances = disturbances
    }
}
