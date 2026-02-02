struct ScenarioMetrics: Hashable {
    let tiltDegrees: [MetricSample]
    let omega: [MetricSample]
    let timeRange: ClosedRange<Double>
    let maxTiltDegrees: Double
    let maxOmega: Double
}
