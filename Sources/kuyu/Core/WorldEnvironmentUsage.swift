public struct WorldEnvironmentUsage: Sendable, Codable, Equatable {
    public let useGravity: Bool
    public let useWind: Bool
    public let useAtmosphere: Bool

    public init(useGravity: Bool, useWind: Bool, useAtmosphere: Bool) {
        self.useGravity = useGravity
        self.useWind = useWind
        self.useAtmosphere = useAtmosphere
    }

    public static let none = WorldEnvironmentUsage(
        useGravity: false,
        useWind: false,
        useAtmosphere: false
    )

    public static let gravityOnly = WorldEnvironmentUsage(
        useGravity: true,
        useWind: false,
        useAtmosphere: false
    )

    public static let full = WorldEnvironmentUsage(
        useGravity: true,
        useWind: true,
        useAtmosphere: true
    )
}
