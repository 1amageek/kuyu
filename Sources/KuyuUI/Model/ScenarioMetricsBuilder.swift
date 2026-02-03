import Foundation
import KuyuCore

struct ScenarioMetricsBuilder {
    static func build(log: SimulationLog, maxPoints: Int = 1200) -> ScenarioMetrics {
        let events = log.events
        guard let first = events.first, let last = events.last else {
            return ScenarioMetrics(
                tiltDegrees: [],
                omega: [],
                speed: [],
                altitude: [],
                timeRange: 0...0,
                maxTiltDegrees: 0,
                maxOmega: 0,
                maxSpeed: 0,
                maxAltitude: 0
            )
        }

        let strideValue = max(1, events.count / maxPoints)
        var tiltSamples: [MetricSample] = []
        var omegaSamples: [MetricSample] = []
        var speedSamples: [MetricSample] = []
        var altitudeSamples: [MetricSample] = []
        tiltSamples.reserveCapacity(events.count / strideValue + 1)
        omegaSamples.reserveCapacity(events.count / strideValue + 1)
        speedSamples.reserveCapacity(events.count / strideValue + 1)
        altitudeSamples.reserveCapacity(events.count / strideValue + 1)

        var maxTilt: Double = 0
        var maxOmega: Double = 0
        var maxSpeed: Double = 0
        var maxAltitude: Double = 0

        var index = 0
        while index < events.count {
            let event = events[index]
            let time = event.time.time
            let tiltDegrees = event.safetyTrace.tiltRadians * 180.0 / Double.pi
            let omega = event.safetyTrace.omegaMagnitude
            let velocity = event.stateSnapshot.velocity
            let speed = sqrt(velocity.x * velocity.x + velocity.y * velocity.y + velocity.z * velocity.z)
            let altitude = event.stateSnapshot.position.z

            maxTilt = max(maxTilt, tiltDegrees)
            maxOmega = max(maxOmega, omega)
            maxSpeed = max(maxSpeed, speed)
            maxAltitude = max(maxAltitude, altitude)

            tiltSamples.append(MetricSample(time: time, value: tiltDegrees))
            omegaSamples.append(MetricSample(time: time, value: omega))
            speedSamples.append(MetricSample(time: time, value: speed))
            altitudeSamples.append(MetricSample(time: time, value: altitude))

            index += strideValue
        }

        if let lastEvent = events.last, lastEvent.time.time != tiltSamples.last?.time {
            let time = lastEvent.time.time
            let tiltDegrees = lastEvent.safetyTrace.tiltRadians * 180.0 / Double.pi
            let omega = lastEvent.safetyTrace.omegaMagnitude
            let velocity = lastEvent.stateSnapshot.velocity
            let speed = sqrt(velocity.x * velocity.x + velocity.y * velocity.y + velocity.z * velocity.z)
            let altitude = lastEvent.stateSnapshot.position.z
            maxTilt = max(maxTilt, tiltDegrees)
            maxOmega = max(maxOmega, omega)
            maxSpeed = max(maxSpeed, speed)
            maxAltitude = max(maxAltitude, altitude)
            tiltSamples.append(MetricSample(time: time, value: tiltDegrees))
            omegaSamples.append(MetricSample(time: time, value: omega))
            speedSamples.append(MetricSample(time: time, value: speed))
            altitudeSamples.append(MetricSample(time: time, value: altitude))
        }

        return ScenarioMetrics(
            tiltDegrees: tiltSamples,
            omega: omegaSamples,
            speed: speedSamples,
            altitude: altitudeSamples,
            timeRange: first.time.time...last.time.time,
            maxTiltDegrees: maxTilt,
            maxOmega: maxOmega,
            maxSpeed: maxSpeed,
            maxAltitude: maxAltitude
        )
    }
}
