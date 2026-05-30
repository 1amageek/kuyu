import Foundation
import KuyuCore

struct RobotPoseSnapshot {
    let roll: Double
    let pitch: Double
    let yaw: Double
    let position: Axis3
    let renderInfo: RenderAssetInfo?
    let jointAngles: [Double]
    let jointValues: [String: Double]
    let actuatorChannels: [ActuatorChannelSnapshot]
    let sensorSamples: [ChannelSample]
    let stepIndex: UInt64?
    let time: Double?

    @MainActor
    static func current(model: SimulationViewModel) -> RobotPoseSnapshot {
        if !model.isRunning,
           !model.isLoopRunning,
           let replay = replaySnapshot(model: model) {
            return replay
        }

        let scene = model.liveScene
        let robot = scene?.bodies.first
        let angles = robot.map { eulerAngles(from: $0.orientation) } ?? (roll: 0, pitch: 0, yaw: 0)
        let joints = jointState(from: scene?.scalars ?? [:], model: model)
        return RobotPoseSnapshot(
            roll: angles.roll,
            pitch: angles.pitch,
            yaw: angles.yaw,
            position: robot?.position ?? Axis3(x: 0, y: 0, z: 0),
            renderInfo: model.renderAssetInfo(),
            jointAngles: joints.ordered,
            jointValues: joints.byID,
            actuatorChannels: model.lastActuatorTelemetry?.channels ?? [],
            sensorSamples: model.lastSensorSamples,
            stepIndex: nil,
            time: scene?.time
        )
    }

    @MainActor
    private static func replaySnapshot(model: SimulationViewModel) -> RobotPoseSnapshot? {
        guard let events = model.selectedScenario?.log.events, !events.isEmpty else {
            return nil
        }
        let clampedFraction = min(max(model.simulationPlaybackFraction, 0), 1)
        let index = min(events.count - 1, Int((Double(events.count - 1) * clampedFraction).rounded()))
        let root = events[index].plantState.root
        let angles = eulerAngles(from: root.orientation)
        let joints = jointState(from: events[index].plantState.scalars, model: model)
        return RobotPoseSnapshot(
            roll: angles.roll,
            pitch: angles.pitch,
            yaw: angles.yaw,
            position: root.position,
            renderInfo: model.renderAssetInfo(),
            jointAngles: joints.ordered,
            jointValues: joints.byID,
            actuatorChannels: events[index].actuatorTelemetry.channels,
            sensorSamples: events[index].sensorSamples,
            stepIndex: events[index].time.stepIndex,
            time: events[index].time.time
        )
    }

    @MainActor
    static func jointState(
        from scalars: [String: Double],
        model: SimulationViewModel
    ) -> (ordered: [Double], byID: [String: Double]) {
        if let embodiment = model.currentEmbodiment() {
            let actuatorSignals = embodiment.signals.actuator.sorted { $0.index < $1.index }
            let ordered = actuatorSignals.map { scalars[$0.id] ?? 0.0 }
            if !ordered.isEmpty {
                return (ordered, scalars)
            }
        }

        let pairs = scalars
            .filter { $0.key.hasPrefix("joint_") }
            .sorted { $0.key < $1.key }
        return (
            pairs.map(\.value),
            Dictionary(uniqueKeysWithValues: pairs)
        )
    }

    private static func eulerAngles(from quaternion: QuaternionSnapshot) -> (roll: Double, pitch: Double, yaw: Double) {
        let w = quaternion.w
        let x = quaternion.x
        let y = quaternion.y
        let z = quaternion.z

        let sinr = 2 * (w * x + y * z)
        let cosr = 1 - 2 * (x * x + y * y)
        let roll = atan2(sinr, cosr)

        let sinp = 2 * (w * y - z * x)
        let pitch = abs(sinp) >= 1 ? (Double.pi / 2) * (sinp > 0 ? 1 : -1) : asin(sinp)

        let siny = 2 * (w * z + x * y)
        let cosy = 1 - 2 * (y * y + z * z)
        let yaw = atan2(siny, cosy)

        return (roll, pitch, yaw)
    }
}
