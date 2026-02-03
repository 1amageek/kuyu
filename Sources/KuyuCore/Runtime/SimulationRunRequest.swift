public enum ControllerSelection: String, CaseIterable, Identifiable, Sendable {
    case baseline = "Baseline"
    case manasMLX = "ManasMLX"

    public var id: String { rawValue }
}

public struct SimulationRunRequest: Sendable {
    public let controller: ControllerSelection
    public let gains: ImuRateDampingCutGains
    public let cutPeriodSteps: UInt64
    public let noise: IMU6NoiseConfig
    public let determinism: DeterminismConfig
    public let modelDescriptorPath: String
    public let overrideParameters: QuadrotorParameters?
    public let useAux: Bool
    public let useQualityGating: Bool

    public init(
        controller: ControllerSelection,
        gains: ImuRateDampingCutGains,
        cutPeriodSteps: UInt64,
        noise: IMU6NoiseConfig,
        determinism: DeterminismConfig,
        modelDescriptorPath: String,
        overrideParameters: QuadrotorParameters?,
        useAux: Bool,
        useQualityGating: Bool
    ) {
        self.controller = controller
        self.gains = gains
        self.cutPeriodSteps = cutPeriodSteps
        self.noise = noise
        self.determinism = determinism
        self.modelDescriptorPath = modelDescriptorPath
        self.overrideParameters = overrideParameters
        self.useAux = useAux
        self.useQualityGating = useQualityGating
    }
}
