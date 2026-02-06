import Testing
import KuyuProfiles
@testable import KuyuCore

@Test func failurePolicyDetectsSimulationIntegrity() async throws {
    let envelope = try SafetyEnvelope(
        omegaSafeMax: 10.0,
        tiltSafeMaxDegrees: 45.0,
        sustainedViolationSeconds: 0.2,
        groundZ: 0.0,
        fallDurationSeconds: 0.3,
        fallVelocityThreshold: 0.1
    )
    var policy = SafetyFailurePolicy(envelope: envelope, timeStep: 0.1)

    let log = try makeLog(
        time: 0.1,
        omega: .nan,
        tilt: 0.0,
        positionZ: 1.0,
        velocityZ: 0.0
    )

    let event = policy.update(log: log)
    #expect(event?.reason == .simulationIntegrity)
}

@Test func failurePolicyDetectsSafetyEnvelope() async throws {
    let envelope = try SafetyEnvelope(
        omegaSafeMax: 1.0,
        tiltSafeMaxDegrees: 10.0,
        sustainedViolationSeconds: 0.2,
        groundZ: 0.0,
        fallDurationSeconds: 0.5,
        fallVelocityThreshold: 0.1
    )
    var policy = SafetyFailurePolicy(envelope: envelope, timeStep: 0.1)

    let log = try makeLog(time: 0.1, omega: 2.0, tilt: 0.0, positionZ: 1.0, velocityZ: 0.0)
    _ = policy.update(log: log)
    let event = policy.update(log: log)
    #expect(event?.reason == .safetyEnvelope)
}

@Test func failurePolicyDetectsGroundViolation() async throws {
    let envelope = try SafetyEnvelope(
        omegaSafeMax: 10.0,
        tiltSafeMaxDegrees: 45.0,
        sustainedViolationSeconds: 0.2,
        groundZ: 0.0,
        fallDurationSeconds: 0.5,
        fallVelocityThreshold: 0.1
    )
    var policy = SafetyFailurePolicy(envelope: envelope, timeStep: 0.1)

    let log = try makeLog(time: 0.1, omega: 0.0, tilt: 0.0, positionZ: -0.01, velocityZ: 0.0)
    let event = policy.update(log: log)
    #expect(event?.reason == .groundViolation)
}

@Test func failurePolicyDetectsSustainedFall() async throws {
    let envelope = try SafetyEnvelope(
        omegaSafeMax: 10.0,
        tiltSafeMaxDegrees: 45.0,
        sustainedViolationSeconds: 0.2,
        groundZ: 0.0,
        fallDurationSeconds: 0.2,
        fallVelocityThreshold: 0.1
    )
    var policy = SafetyFailurePolicy(envelope: envelope, timeStep: 0.1)

    let log = try makeLog(time: 0.1, omega: 0.0, tilt: 0.0, positionZ: 1.0, velocityZ: -0.2)
    _ = policy.update(log: log)
    let event = policy.update(log: log)
    #expect(event?.reason == .sustainedFall)
}

private func makeLog(
    time: Double,
    omega: Double,
    tilt: Double,
    positionZ: Double,
    velocityZ: Double
) throws -> WorldStepLog {
    let worldTime = try WorldTime(stepIndex: 1, time: time)
    let root = RigidBodySnapshot(
        id: "root",
        position: Axis3(x: 0, y: 0, z: positionZ),
        velocity: Axis3(x: 0, y: 0, z: velocityZ),
        orientation: QuaternionSnapshot(w: 1, x: 0, y: 0, z: 0),
        angularVelocity: Axis3(x: 0, y: 0, z: 0)
    )
    let safety = SafetyTrace(omegaMagnitude: omega, tiltRadians: tilt)
    return WorldStepLog(
        time: worldTime,
        events: [],
        sensorSamples: [],
        driveIntents: [],
        reflexCorrections: [],
        actuatorValues: [],
        actuatorTelemetry: ActuatorTelemetrySnapshot(channels: []),
        safetyTrace: safety,
        plantState: PlantStateSnapshot(root: root),
        disturbances: DisturbanceSnapshot(forceWorld: Axis3(x: 0, y: 0, z: 0), torqueBody: Axis3(x: 0, y: 0, z: 0))
    )
}
