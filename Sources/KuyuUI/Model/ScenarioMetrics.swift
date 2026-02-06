public struct ScenarioMetrics: Hashable {
    let tiltDegrees: [MetricSample]
    let omega: [MetricSample]
    let speed: [MetricSample]
    let altitude: [MetricSample]
    let timeRange: ClosedRange<Double>
    let maxTiltDegrees: Double
    let maxOmega: Double
    let maxSpeed: Double
    let maxAltitude: Double
}
