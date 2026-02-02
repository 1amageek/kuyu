import Foundation
import kuyu

struct ScenarioMetricsBuilder {
    static func build(log: SimulationLog, maxPoints: Int = 1200) -> ScenarioMetrics {
        let events = log.events
        guard let first = events.first, let last = events.last else {
            return ScenarioMetrics(
                tiltDegrees: [],
                omega: [],
                timeRange: 0...0,
                maxTiltDegrees: 0,
                maxOmega: 0
            )
        }

        let strideValue = max(1, events.count / maxPoints)
        var tiltSamples: [MetricSample] = []
        var omegaSamples: [MetricSample] = []
        tiltSamples.reserveCapacity(events.count / strideValue + 1)
        omegaSamples.reserveCapacity(events.count / strideValue + 1)

        var maxTilt: Double = 0
        var maxOmega: Double = 0

        var index = 0
        while index < events.count {
            let event = events[index]
            let time = event.time.time
            let tiltDegrees = event.safetyTrace.tiltRadians * 180.0 / Double.pi
            let omega = event.safetyTrace.omegaMagnitude

            maxTilt = max(maxTilt, tiltDegrees)
            maxOmega = max(maxOmega, omega)

            tiltSamples.append(MetricSample(time: time, value: tiltDegrees))
            omegaSamples.append(MetricSample(time: time, value: omega))

            index += strideValue
        }

        if let lastEvent = events.last, lastEvent.time.time != tiltSamples.last?.time {
            let time = lastEvent.time.time
            let tiltDegrees = lastEvent.safetyTrace.tiltRadians * 180.0 / Double.pi
            let omega = lastEvent.safetyTrace.omegaMagnitude
            maxTilt = max(maxTilt, tiltDegrees)
            maxOmega = max(maxOmega, omega)
            tiltSamples.append(MetricSample(time: time, value: tiltDegrees))
            omegaSamples.append(MetricSample(time: time, value: omega))
        }

        return ScenarioMetrics(
            tiltDegrees: tiltSamples,
            omega: omegaSamples,
            timeRange: first.time.time...last.time.time,
            maxTiltDegrees: maxTilt,
            maxOmega: maxOmega
        )
    }
}
