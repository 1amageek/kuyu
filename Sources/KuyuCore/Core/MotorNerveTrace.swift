public struct MotorNerveTrace: Sendable, Codable, Equatable {
    public let uRaw: [Double]
    public let uSat: [Double]
    public let uRate: [Double]
    public let uOut: [Double]
    public let failsafeActive: Bool

    public init(
        uRaw: [Double],
        uSat: [Double],
        uRate: [Double],
        uOut: [Double],
        failsafeActive: Bool
    ) {
        self.uRaw = uRaw
        self.uSat = uSat
        self.uRate = uRate
        self.uOut = uOut
        self.failsafeActive = failsafeActive
    }
}
