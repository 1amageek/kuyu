import Foundation
import Testing
import KuyuCore
import KuyuPhysics
import KuyuScenarios

@Test func bundledRobotManifestsLoadNativeBodyWorldAndEmbodimentContracts() async throws {
    let quad = try loadBundledRobot(relativePath: "Sources/KuyuUI/Resources/Models/QuadRef/quadref.kuyurobot.json")
    let single = try loadBundledRobot(relativePath: "Sources/KuyuUI/Resources/Models/SingleProp/singleprop.kuyurobot.json")
    let roarm = try loadBundledRobot(relativePath: "Sources/KuyuUI/Resources/Models/RoArmM1/roarm-m1.kuyurobot.json")

    #expect(quad.manifest.robotID == "quadref-v0")
    #expect(quad.body.bodyID == "quadref-body-v0")
    #expect(quad.embodiment.contractID == "quadref-embodiment-v0")
    #expect(single.manifest.robotID == "singleprop-v0")
    #expect(single.body.bodyID == "singleprop-body-v0")
    #expect(single.embodiment.contractID == "singleprop-embodiment-v0")
    #expect(roarm.manifest.robotID == "roarm-m1-v0")
    #expect(roarm.body.bodyID == "roarm-m1-body-v0")
    #expect(roarm.embodiment.contractID == "roarm-m1-embodiment-v0")
}

@Test func bundledRoArmM1PassesDynamicReadinessAndRejectsContactTraining() async throws {
    let loaded = try loadBundledRobot(relativePath: "Sources/KuyuUI/Resources/Models/RoArmM1/roarm-m1.kuyurobot.json")
    let gate = ReadinessGate()

    let level = try gate.validate(
        body: loaded.body,
        world: loaded.world,
        embodiment: loaded.embodiment,
        report: loaded.compatibilityReport,
        requiredLevel: .dynamicSimulation
    )
    #expect(level == .dynamicSimulation)

    #expect(throws: KuyuModelValidationError.self) {
        _ = try gate.validate(
            body: loaded.body,
            world: loaded.world,
            embodiment: loaded.embodiment,
            report: loaded.compatibilityReport,
            requiredLevel: .contactTraining
        )
    }
}

@Test func dynamicReadinessRejectsUnderqualifiedCompatibilityReport() async throws {
    let loaded = try loadBundledRobot(relativePath: "Sources/KuyuUI/Resources/Models/RoArmM1/roarm-m1.kuyurobot.json")
    let report = CompatibilityReport(
        schemaVersion: "kuyu.compatibility.v1",
        reportID: "underqualified",
        sourceFormat: "test",
        targetContract: "KuyuBodyModel",
        mappings: [],
        readinessLevel: .kinematicPreview
    )

    #expect(throws: KuyuModelValidationError.unsupportedReadiness("compatibility.kinematicPreview")) {
        _ = try ReadinessGate().validate(
            body: loaded.body,
            world: loaded.world,
            embodiment: loaded.embodiment,
            report: report,
            requiredLevel: .dynamicSimulation
        )
    }
}

@Test func dynamicReadinessRejectsBodyEmbodimentAttachmentMismatch() async throws {
    let loaded = try loadBundledRobot(relativePath: "Sources/KuyuUI/Resources/Models/RoArmM1/roarm-m1.kuyurobot.json")
    let invalidBody = KuyuBodyModel(
        schemaVersion: loaded.body.schemaVersion,
        bodyID: loaded.body.bodyID,
        name: loaded.body.name,
        category: loaded.body.category,
        provenance: loaded.body.provenance,
        units: loaded.body.units,
        frames: loaded.body.frames,
        links: loaded.body.links,
        joints: loaded.body.joints,
        materials: loaded.body.materials,
        actuatorAttachments: loaded.body.actuatorAttachments.map { attachment in
            if attachment.jointID == "joint_1" {
                return ActuatorAttachment(
                    actuatorID: "missing-servo",
                    jointID: attachment.jointID,
                    transmissionRatio: attachment.transmissionRatio,
                    torqueLimit: attachment.torqueLimit
                )
            }
            return attachment
        },
        sensorMounts: loaded.body.sensorMounts
    )

    #expect(throws: KuyuModelValidationError.unknownReference("readiness.actuatorAttachments.missing-servo")) {
        _ = try ReadinessGate().validate(
            body: invalidBody,
            world: loaded.world,
            embodiment: loaded.embodiment,
            report: nil,
            requiredLevel: .dynamicSimulation
        )
    }
}

@Test func bundledRoArmM1MapsThroughMotorNerveBeforeHardwareEncoding() async throws {
    let loaded = try loadBundledRobot(relativePath: "Sources/KuyuUI/Resources/Models/RoArmM1/roarm-m1.kuyurobot.json")
    var chain = try MotorNerveChain(contract: loaded.embodiment)

    let drives = [
        try DriveIntent(index: DriveIndex(0), activation: 0.0),
        try DriveIntent(index: DriveIndex(1), activation: 0.0),
        try DriveIntent(index: DriveIndex(2), activation: 0.0),
        try DriveIntent(index: DriveIndex(3), activation: 0.0),
        try DriveIntent(index: DriveIndex(4), activation: 0.0),
    ]
    let actuators = try chain.update(
        input: drives,
        corrections: [],
        telemetry: MotorNerveTelemetry(actuatorTelemetry: ActuatorTelemetrySnapshot(channels: [])),
        time: try WorldTime(stepIndex: 0, time: 0.0)
    )
    let command = try RoArmM1ServoCommandEncoder().command(forActuatorValues: actuators)

    #expect(command.positions == [2047, 2047, 2047, 2047, 2047])
}

@Test(.timeLimit(.minutes(1))) func roArmM1ArticulatedDynamicsIsDeterministicAndFinite() async throws {
    let loaded = try loadBundledRobot(relativePath: "Sources/KuyuUI/Resources/Models/RoArmM1/roarm-m1.kuyurobot.json")
    let simulator = ArticulatedRigidBodySimulator()
    let request = ArticulatedRigidBodySimulationRequest(
        body: loaded.body,
        world: loaded.world,
        embodiment: loaded.embodiment,
        compatibilityReport: loaded.compatibilityReport,
        determinism: .tier0Strict,
        readinessLevel: .dynamicSimulation,
        duration: 0.5,
        timeStep: try TimeStep(delta: loaded.world.time.fixedStepSeconds),
        seed: ScenarioSeed(42)
    )

    let first = try await simulator.run(request: request)
    let second = try await simulator.run(request: request)

    #expect(first == second)
    #expect(first.events.isEmpty == false)
    for event in first.events {
        for value in event.plantState.scalars.values {
            #expect(value.isFinite)
        }
    }
}

private func loadBundledRobot(relativePath: String) throws -> LoadedKuyuRobot {
    let testFileURL = URL(fileURLWithPath: #filePath)
    let packageRoot = testFileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let path = packageRoot.appendingPathComponent(relativePath).path
    return try KuyuModelLoader().loadRobot(path: path)
}
