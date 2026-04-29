import Foundation
import KuyuCore
import KuyuPhysics
import KuyuScenarios

struct LiveTelemetryPresentation {
    let liveSampleStride: Int
    let sensorSamples: [ChannelSample]
    let actuatorValues: [ActuatorValue]
    let driveIntents: [DriveIntent]
    let reflexCorrections: [ReflexCorrection]
    let actuatorTelemetry: ActuatorTelemetrySnapshot
    let motorNerveTrace: MotorNerveTrace?
    let sceneState: SceneState
    let strideLogMetadata: [String: String]?
    let stepLogMetadata: [String: String]?
}

struct TelemetryPresenter {
    private let targetRenderFPS: Double
    private(set) var liveSampleStride: Int
    private var autoStridePending = true
    private var lastLiveStepTime: Double?
    private var lastTelemetryLogTime: Double?

    init(targetRenderFPS: Double = 30.0, initialSampleStride: Int = 33) {
        self.targetRenderFPS = targetRenderFPS
        self.liveSampleStride = max(1, initialSampleStride)
    }

    mutating func resetStride() {
        autoStridePending = true
        lastLiveStepTime = nil
    }

    mutating func present(
        step: WorldStepLog,
        taskMode: SimulationTaskMode,
        activeParameters: ReferenceQuadrotorParameters?,
        isActive: Bool
    ) -> LiveTelemetryPresentation? {
        let strideLog = updateLiveStrideIfNeeded(step: step, taskMode: taskMode)
        let stride = autoStridePending ? 1 : max(1, liveSampleStride)
        if (step.time.stepIndex % UInt64(stride)) != 0 { return nil }

        let root = step.plantState.root
        let body = BodySceneState(
            id: root.id,
            position: root.position,
            velocity: root.velocity,
            orientation: root.orientation,
            angularVelocity: root.angularVelocity
        )
        let scene = SceneState(time: step.time.time, bodies: [body])
        let stepLog = isActive ? stepLogMetadata(
            step: step,
            taskMode: taskMode,
            activeParameters: activeParameters
        ) : nil

        return LiveTelemetryPresentation(
            liveSampleStride: liveSampleStride,
            sensorSamples: step.sensorSamples,
            actuatorValues: step.actuatorValues,
            driveIntents: step.driveIntents,
            reflexCorrections: step.reflexCorrections,
            actuatorTelemetry: step.actuatorTelemetry,
            motorNerveTrace: step.motorNerveTrace,
            sceneState: scene,
            strideLogMetadata: strideLog,
            stepLogMetadata: stepLog
        )
    }

    private mutating func updateLiveStrideIfNeeded(
        step: WorldStepLog,
        taskMode: SimulationTaskMode
    ) -> [String: String]? {
        guard autoStridePending else { return nil }
        defer { lastLiveStepTime = step.time.time }
        guard let last = lastLiveStepTime else { return nil }

        let dt = step.time.time - last
        guard dt > 0 else { return nil }

        let desiredStride = max(1, Int(round((1.0 / targetRenderFPS) / dt)))
        liveSampleStride = desiredStride
        autoStridePending = false
        return [
            "action": "renderStrideAuto",
            "task": taskMode.rawValue,
            "dt": String(format: "%.4f", dt),
            "stride": "\(desiredStride)",
            "targetFps": String(format: "%.1f", targetRenderFPS),
        ]
    }

    private mutating func stepLogMetadata(
        step: WorldStepLog,
        taskMode: SimulationTaskMode,
        activeParameters: ReferenceQuadrotorParameters?
    ) -> [String: String]? {
        let now = step.time.time
        let last = lastTelemetryLogTime ?? -Double.greatestFiniteMagnitude
        guard now - last >= 1.0 else { return nil }
        lastTelemetryLogTime = now

        let root = step.plantState.root
        var metadata: [String: String] = [
            "action": "telemetryStep",
            "task": taskMode.rawValue,
            "t": String(format: "%.2f", now),
            "step": "\(step.time.stepIndex)",
            "pos": String(format: "%.2f,%.2f,%.2f", root.position.x, root.position.y, root.position.z),
            "vel": String(format: "%.2f,%.2f,%.2f", root.velocity.x, root.velocity.y, root.velocity.z),
        ]

        guard taskMode == .singleLift else { return metadata }

        let accelZ = step.sensorSamples.first(where: { $0.channelIndex == 5 })?.value
        let drive = step.driveIntents.first?.activation
        let uRaw = step.motorNerveTrace?.uRaw.first
        let uOut = step.motorNerveTrace?.uOut.first
        if let activeParameters {
            let disturbanceZ = step.disturbances.forceWorld.z
            let thrust = step.actuatorTelemetry.value(for: "motor1") ?? 0
            let netAccelZ = (thrust + disturbanceZ) / activeParameters.mass - activeParameters.gravity
            metadata["netAccelZ"] = String(format: "%.3f", netAccelZ)
            metadata["gravity"] = String(format: "%.3f", activeParameters.gravity)
            metadata["mass"] = String(format: "%.3f", activeParameters.mass)
            if let uOut {
                let expectedThrust = uOut * activeParameters.maxThrust
                let thrustError = thrust - expectedThrust
                metadata["u_out_thrust"] = String(format: "%.3f", expectedThrust)
                metadata["thrustError"] = String(format: "%.3f", thrustError)
            } else {
                metadata["u_out_thrust"] = "n/a"
                metadata["thrustError"] = "n/a"
            }
        }
        metadata["accelZ"] = accelZ.map { String(format: "%.3f", $0) } ?? "n/a"
        metadata["drive"] = drive.map { String(format: "%.3f", $0) } ?? "n/a"
        metadata["u_raw"] = uRaw.map { String(format: "%.3f", $0) } ?? "n/a"
        metadata["u_out"] = uOut.map { String(format: "%.3f", $0) } ?? "n/a"
        let thrust = step.actuatorTelemetry.value(for: "motor1") ?? 0
        metadata["thrust"] = String(format: "%.3f", thrust)
        return metadata
    }
}
