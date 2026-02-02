import kuyu

struct SimulationRunRequest: Sendable {
    let gains: ImuRateDampingCutGains
    let cutPeriodSteps: UInt64
    let noise: IMU6NoiseConfig
    let determinism: DeterminismConfig
    let learningMode: LearningMode
    let modelDescriptorPath: String
    let overrideParameters: QuadrotorParameters?
}
