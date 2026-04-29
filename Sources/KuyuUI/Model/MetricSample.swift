public struct MetricSample: Identifiable, Hashable, Sendable {
    public let id: Double
    let time: Double
    let value: Double

    public init(time: Double, value: Double) {
        self.time = time
        self.value = value
        self.id = time
    }
}
