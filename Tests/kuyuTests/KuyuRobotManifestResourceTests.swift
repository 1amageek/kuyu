import EmbodimentContract
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

@Test func bundledRoArmM1RejectsHardwareParityWithoutMeasuredReport() async throws {
    let loaded = try loadBundledRobot(relativePath: "Sources/KuyuUI/Resources/Models/RoArmM1/roarm-m1.kuyurobot.json")

    #expect(throws: KuyuModelValidationError.empty("hardwareParity.report")) {
        _ = try ReadinessGate().validate(
            body: loaded.body,
            world: loaded.world,
            embodiment: loaded.embodiment,
            report: loaded.compatibilityReport,
            requiredLevel: .hardwareParity
        )
    }
}

@Test func bundledRoArmM1DescriptorCorpusAcceptanceRecordsHardwareParityGap() async throws {
    let loaded = try loadBundledRobot(relativePath: "Sources/KuyuUI/Resources/Models/RoArmM1/roarm-m1.kuyurobot.json")
    let timeStep = loaded.world.time.fixedStepSeconds
    let entry = DescriptorCorpusEntry(
        loadedRobot: loaded,
        entryID: "bundled-roarm-m1-real-profile-dynamic",
        label: "Bundled RoArm M1 real-profile dynamic descriptor",
        hardwareReport: try roArmM1DynamicHardwareCalibrationReport(loaded: loaded),
        requiredReadiness: .dynamicSimulation,
        duration: timeStep * 4.0,
        timeStep: try TimeStep(delta: timeStep),
        seed: ScenarioSeed(42),
        determinism: try DeterminismConfig(tier: .tier0)
    )

    let summary = try await DescriptorCorpusAcceptanceService().accept(
        corpusID: "bundled-real-profile-descriptor-corpus",
        entries: [entry],
        generatedAt: "2026-06-29T00:00:00Z"
    )
    let record = try #require(summary.records.first)
    let gap = try #require(summary.hardwareParityGaps.first)

    #expect(summary.accepted)
    #expect(record.accepted)
    #expect(record.robotID == "roarm-m1-v0")
    #expect(record.bodyID == loaded.body.bodyID)
    #expect(record.worldID == loaded.world.worldID)
    #expect(record.embodimentContractID == loaded.embodiment.contractID)
    #expect(record.achievedReadiness == .dynamicSimulation)
    #expect(record.hardwareParity != .accepted)
    #expect(gap.entryID == record.entryID)
    #expect(gap.readinessLevel == .hardwareParity)
    #expect(gap.reason.contains("insufficientCoverage"))
    #expect(record.replay.passed)
    #expect(record.replay.sortedJSONByteStable)
    #expect(record.replay.stepCount == 4)
}

@Test func bundledRealProfileDescriptorCorpusAcceptsManipulatorAndAerialReferences() async throws {
    let roarm = try loadBundledRobot(relativePath: "Sources/KuyuUI/Resources/Models/RoArmM1/roarm-m1.kuyurobot.json")
    let quad = try loadBundledRobot(relativePath: "Sources/KuyuUI/Resources/Models/QuadRef/quadref.kuyurobot.json")
    let single = try loadBundledRobot(relativePath: "Sources/KuyuUI/Resources/Models/SingleProp/singleprop.kuyurobot.json")
    let entries = try [
        descriptorCorpusEntry(
            loaded: roarm,
            entryID: "bundled-roarm-m1-real-profile-dynamic",
            label: "Bundled RoArm M1 real-profile dynamic descriptor",
            seed: 42,
            hardwareReport: try roArmM1DynamicHardwareCalibrationReport(loaded: roarm)
        ),
        descriptorCorpusEntry(
            loaded: quad,
            entryID: "bundled-quadref-real-profile-dynamic",
            label: "Bundled QuadRef real-profile dynamic descriptor",
            seed: 43
        ),
        descriptorCorpusEntry(
            loaded: single,
            entryID: "bundled-singleprop-real-profile-dynamic",
            label: "Bundled SingleProp real-profile dynamic descriptor",
            seed: 44
        )
    ]

    let summary = try await DescriptorCorpusAcceptanceService().accept(
        corpusID: "bundled-real-profile-descriptor-corpus",
        entries: entries,
        generatedAt: "2026-06-30T00:00:00Z"
    )
    let artifactDirectory = temporaryDescriptorCorpusDirectory()
    defer {
        do {
            try FileManager.default.removeItem(at: artifactDirectory)
        } catch {
            Issue.record("Temporary descriptor corpus directory cleanup failed: \(error)")
        }
    }
    let artifactURL = try DescriptorCorpusAcceptanceArtifactStore().write(summary, to: artifactDirectory)
    let persistedSummary = try DescriptorCorpusAcceptanceArtifactStore().validatedSummary(at: artifactURL)
    let recordsByRobotID = Dictionary(uniqueKeysWithValues: summary.records.map { ($0.robotID, $0) })
    let roarmRecord = try #require(recordsByRobotID["roarm-m1-v0"])
    let quadRecord = try #require(recordsByRobotID["quadref-v0"])
    let singleRecord = try #require(recordsByRobotID["singleprop-v0"])
    let gap = try #require(summary.hardwareParityGaps.first)

    #expect(artifactURL.lastPathComponent == DescriptorCorpusAcceptanceArtifactStore.fileName)
    #expect(persistedSummary == summary)
    #expect(summary.accepted)
    #expect(summary.records.count == 3)
    #expect(summary.records.map(\.robotID).sorted() == ["quadref-v0", "roarm-m1-v0", "singleprop-v0"])
    #expect(summary.records.allSatisfy { $0.accepted })
    #expect(summary.records.allSatisfy { $0.achievedReadiness == .dynamicSimulation })
    #expect(summary.records.allSatisfy { $0.replay.passed })
    #expect(summary.records.allSatisfy { $0.replay.sortedJSONByteStable })
    #expect(summary.records.allSatisfy { $0.replay.stepCount == 4 })
    #expect(roarmRecord.hardwareParity != .accepted)
    #expect(quadRecord.hardwareParity == .notRequested)
    #expect(singleRecord.hardwareParity == .notRequested)
    #expect(gap.entryID == roarmRecord.entryID)
    #expect(gap.readinessLevel == .hardwareParity)
    #expect(summary.hardwareParityGaps.count == 1)
}

@Test func bundledRoArmM1DeclaresFifthDriveAsGripperClampAndPreservesMimicGraph() async throws {
    let loaded = try loadBundledRobot(relativePath: "Sources/KuyuUI/Resources/Models/RoArmM1/roarm-m1.kuyurobot.json")
    let sensors = loaded.embodiment.signals.sensor.sorted { $0.index < $1.index }
    let actuators = loaded.embodiment.signals.actuator.sorted { $0.index < $1.index }
    let drives = loaded.embodiment.signals.drive.sorted { $0.index < $1.index }
    let reflexes = loaded.embodiment.signals.reflex.sorted { $0.index < $1.index }
    let gripperIndex = 4

    #expect(sensors[gripperIndex].name == "Gripper clamp angle")
    #expect(sensors[gripperIndex].group == "gripper-proprioception")
    #expect(actuators[gripperIndex].name == "Gripper clamp actuator command")
    #expect(actuators[gripperIndex].group == "gripper-actuator")
    #expect(drives[gripperIndex].name == "Drive gripper clamp")
    #expect(drives[gripperIndex].group == "gripper-target")
    #expect(reflexes[gripperIndex].name == "Gripper clamp reflex correction")
    #expect(reflexes[gripperIndex].group == "gripper-reflex")

    let servo = try #require(loaded.embodiment.actuators.first { $0.id == "servo_5" })
    #expect(servo.type.contains("gripper"))
    #expect(servo.channels == ["joint_5"])

    let attachment = try #require(loaded.body.actuatorAttachments.first { $0.actuatorID == "servo_5" })
    #expect(attachment.jointID == "L4_to_L5_1_A")

    let mimicByJointID = Dictionary(uniqueKeysWithValues: loaded.body.joints.compactMap { joint in
        joint.mimic.map { (joint.id, $0) }
    })
    #expect(mimicByJointID.count == 5)
    #expect(mimicByJointID["L4_to_L5_1_B"] == JointMimic(jointID: "L4_to_L5_1_A", multiplier: -1, offset: 0))
    #expect(mimicByJointID["L4_to_L5_2_A"] == JointMimic(jointID: "L4_to_L5_1_A", multiplier: 1, offset: 0))
    #expect(mimicByJointID["L4_to_L5_2_B"] == JointMimic(jointID: "L4_to_L5_1_A", multiplier: -1, offset: 0))
    #expect(mimicByJointID["L5_1_A_to_L5_3_A"] == JointMimic(jointID: "L4_to_L5_1_A", multiplier: -1, offset: 0))
    #expect(mimicByJointID["L5_1_B_to_L5_3_B"] == JointMimic(jointID: "L4_to_L5_1_B", multiplier: -1, offset: 0))
}

@Test func bundledRoArmM1CalibrationPlanUsesSafeCommissioningEnvelope() async throws {
    let loaded = try loadBundledRobot(relativePath: "Sources/KuyuUI/Resources/Models/RoArmM1/roarm-m1.kuyurobot.json")
    let plan = try RoArmM1HardwareCalibrationPlanBuilder().build(
        robot: loaded,
        jointLimits: RoArmM1ServoCommandEncoder.safeCommissioningJointLimits,
        speed: 0,
        acceleration: 60,
        amplitudeRadians: 0.1,
        holdSeconds: 0.5,
        repetitions: 1
    )

    #expect(plan.robotID == "roarm-m1-v0")
    #expect(plan.bodyID == "roarm-m1-body-v0")
    #expect(plan.embodimentContractID == "roarm-m1-embodiment-v0")
    #expect(plan.safetyJointLimits.count == RoArmM1ServoCommandEncoder.jointCount)
    #expect(plan.steps.isEmpty == false)
    #expect(plan.steps[0].stepID == "home-initial")
    #expect(plan.steps[0].commandPulses == [2047, 2047, 2047, 2047, 2047])
    #expect(plan.steps.allSatisfy { $0.commandPayload.contains("\"T\":3") })

    for step in plan.steps {
        for (index, target) in step.jointTargets.enumerated() {
            let limit = RoArmM1ServoCommandEncoder.safeCommissioningJointLimits[index]
            #expect(limit.contains(target.targetRadians))
        }
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
            if attachment.jointID == "base_to_L1" {
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

@Test func bundledRoArmM1DeclaresServoMountsTransmissionsAndCollisionMeshes() async throws {
    let loaded = try loadBundledRobot(relativePath: "Sources/KuyuUI/Resources/Models/RoArmM1/roarm-m1.kuyurobot.json")
    let body = loaded.body
    let mountsByActuatorID = Dictionary(uniqueKeysWithValues: body.actuatorMounts.map { ($0.actuatorID, $0) })
    let attachmentsByActuatorID = Dictionary(uniqueKeysWithValues: body.actuatorAttachments.map { ($0.actuatorID, $0) })

    #expect(body.actuatorMounts.count == 5)
    #expect(body.actuatorAttachments.count == 5)
    #expect(body.links.allSatisfy { !$0.collisions.isEmpty })
    #expect(mountsByActuatorID["servo_1"]?.frameID == "servo_1_output")
    #expect(mountsByActuatorID["servo_2"]?.outputAxis == KuyuVector3(x: 1, y: 0, z: 0))
    #expect(attachmentsByActuatorID["servo_2"]?.transmissionKind == .timingPulley)
    #expect(attachmentsByActuatorID["servo_2"]?.transmissionRatio == 3)
    #expect(attachmentsByActuatorID["servo_2"]?.mechanicalReductionRatio == 3)
    #expect(attachmentsByActuatorID["servo_2"]?.torqueLimit == 8.825985)
    #expect(loaded.embodiment.actuators.first { $0.id == "servo_2" }?.dynamics?.torqueLimit == 2.941995)

    let commandDirections = body.actuatorAttachments
        .sorted { $0.actuatorID < $1.actuatorID }
        .map(\.commandDirection)
    #expect(commandDirections == RoArmM1ServoCommandEncoder.commandDirections)
}

@Test func bundledRoArmM1MatchesManufacturerUrdfKinematicDefinition() async throws {
    let loaded = try loadBundledRobot(relativePath: "Sources/KuyuUI/Resources/Models/RoArmM1/roarm-m1.kuyurobot.json")
    let body = loaded.body
    let manufacturerURDF = try manufacturerRoArmM1URDF()

    #expect(body.links.map(\.id) == manufacturerURDF.links.map(\.name))
    #expect(body.joints.map(\.id) == manufacturerURDF.joints.map(\.name))

    for urdfLink in manufacturerURDF.links {
        let link = try #require(body.links.first { $0.id == urdfLink.name })
        #expect(link.visuals.count == urdfLink.visuals.count)
        #expect(link.collisions.count == urdfLink.visuals.count)

        let urdfVisual = try #require(urdfLink.visuals.first)
        let visual = try #require(link.visuals.first)
        let collision = try #require(link.collisions.first)
        guard case .mesh(let meshPath, let meshScale) = urdfVisual.geometry else {
            Issue.record("Expected manufacturer mesh geometry for \(urdfLink.name)")
            continue
        }

        #expect(visual.kind == .mesh)
        #expect(collision.kind == .mesh)
        #expect(visual.meshPath == meshPath)
        #expect(collision.meshPath == meshPath)
        #expect(visual.meshFormat == .stl)
        #expect(collision.meshFormat == .stl)
        #expect(visual.scale == meshScale.map(kuyuVector))
        #expect(collision.scale == meshScale.map(kuyuVector))
        assertPoseClose(visual.pose, urdfVisual.origin)
        assertPoseClose(collision.pose, urdfVisual.origin)
    }

    for urdfJoint in manufacturerURDF.joints {
        let joint = try #require(body.joints.first { $0.id == urdfJoint.name })
        let limit = try #require(urdfJoint.limit)
        #expect(joint.kind == jointKind(from: urdfJoint.type))
        #expect(joint.parentLinkID == urdfJoint.parent)
        #expect(joint.childLinkID == urdfJoint.child)
        assertPoseClose(joint.origin, urdfJoint.origin)
        assertVectorClose(joint.axis, kuyuVector(urdfJoint.axis))
        assertOptionalClose(joint.lowerLimit, try #require(limit.lower))
        assertOptionalClose(joint.upperLimit, try #require(limit.upper))
        assertOptionalClose(joint.softLowerLimit, try #require(limit.lower))
        assertOptionalClose(joint.softUpperLimit, try #require(limit.upper))
        assertOptionalClose(joint.velocityLimit, try #require(limit.velocity))
        assertOptionalClose(joint.homePosition, 0)
        #expect(joint.mimic == urdfJoint.mimic.map(jointMimic))
    }

    #expect(manufacturerURDF.joints.filter { $0.mimic == nil }.map(\.name) == [
        "base_to_L1",
        "L1_to_L2",
        "L2_to_L3",
        "L3_to_L4",
        "L4_to_L5_1_A"
    ])
}

@Test func bundledRoArmM1RenderUrdfUsesManufacturerMeshTree() async throws {
    let loaded = try loadBundledRobot(relativePath: "Sources/KuyuUI/Resources/Models/RoArmM1/roarm-m1.kuyurobot.json")
    let url = try manufacturerRoArmM1URDFURL()
    let model = try URDFKinematicParser().parse(url: url)
    let meshDirectory = url
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("meshes", isDirectory: true)

    #expect(model.links.map(\.name) == loaded.body.links.map(\.id))
    #expect(model.joints.map(\.name) == loaded.body.joints.map(\.id))

    for link in model.links {
        let visual = try #require(link.visuals.first)
        guard case .mesh(let filename, let scale) = visual.geometry else {
            Issue.record("Expected mesh geometry for \(link.name)")
            continue
        }
        #expect(scale == nil)
        #expect(FileManager.default.fileExists(
            atPath: meshDirectory.appendingPathComponent(filename.lastPathComponentAfterSlash).path
        ))
    }

    for joint in model.joints {
        let bodyJoint = try #require(loaded.body.joints.first { $0.id == joint.name })
        let limit = try #require(joint.limit)
        #expect(joint.type == .revolute)
        assertOptionalClose(bodyJoint.lowerLimit, try #require(limit.lower))
        assertOptionalClose(bodyJoint.upperLimit, try #require(limit.upper))
        #expect(bodyJoint.mimic == joint.mimic.map(jointMimic))
    }
}

@Test func bundledRoArmM1EmbodimentAndServoEncoderRangesMatchDrivenJoints() async throws {
    let loaded = try loadBundledRobot(relativePath: "Sources/KuyuUI/Resources/Models/RoArmM1/roarm-m1.kuyurobot.json")
    let drivenJoints = loaded.body.joints.filter { $0.mimic == nil && $0.kind == .revolute }
    let actuatorSignals = loaded.embodiment.signals.actuator.sorted { $0.index < $1.index }
    let driveSignals = loaded.embodiment.signals.drive.sorted { $0.index < $1.index }
    let sensorSignals = loaded.embodiment.signals.sensor.sorted { $0.index < $1.index }
    let manufacturerDrivenJoints = try manufacturerRoArmM1URDF().joints.filter { $0.mimic == nil }
    let actuatorsByChannel = Dictionary(uniqueKeysWithValues: loaded.embodiment.actuators.compactMap { actuator in
        actuator.channels.first.map { ($0, actuator) }
    })
    let attachmentsByActuatorID = Dictionary(uniqueKeysWithValues: loaded.body.actuatorAttachments.map {
        ($0.actuatorID, $0)
    })

    #expect(drivenJoints.map(\.id) == manufacturerDrivenJoints.map(\.name))
    #expect(actuatorSignals.count == drivenJoints.count)
    #expect(driveSignals.count == drivenJoints.count)
    #expect(sensorSignals.count == drivenJoints.count)
    #expect(RoArmM1ServoCommandEncoder.manufacturerJointLimits.count == drivenJoints.count)

    for index in drivenJoints.indices {
        let joint = drivenJoints[index]
        let encoderLimit = RoArmM1ServoCommandEncoder.manufacturerJointLimits[index]
        let actuatorSignal = actuatorSignals[index]
        let driveSignal = driveSignals[index]
        let sensorSignal = sensorSignals[index]
        let actuator = try #require(actuatorsByChannel[actuatorSignal.id])
        let attachment = try #require(attachmentsByActuatorID[actuator.id])
        let actuatorRange = actuatorPositionRange(
            forJointRange: encoderLimit,
            commandDirection: attachment.commandDirection,
            transmissionRatio: attachment.transmissionRatio
        )

        assertOptionalClose(joint.lowerLimit, encoderLimit.lowerBound)
        assertOptionalClose(joint.upperLimit, encoderLimit.upperBound)
        assertSignalRange(actuatorSignal.range, equals: actuatorRange)
        assertSignalRange(driveSignal.range, equals: encoderLimit)
        assertSignalRange(sensorSignal.range, equals: encoderLimit)
        assertClose(actuator.limits.min, actuatorRange.lowerBound)
        assertClose(actuator.limits.max, actuatorRange.upperBound)
        assertClose(actuator.limits.rateLimitPerSecond, 0.5 * attachment.transmissionRatio)

        let lowerCommand = try RoArmM1ServoCommandEncoder(
            jointLimits: RoArmM1ServoCommandEncoder.manufacturerJointLimits
        ).command(forRadians: RoArmM1ServoCommandEncoder.manufacturerJointLimits.enumerated().map { commandIndex, limit in
            commandIndex == index ? limit.lowerBound : 0
        })
        let upperCommand = try RoArmM1ServoCommandEncoder(
            jointLimits: RoArmM1ServoCommandEncoder.manufacturerJointLimits
        ).command(forRadians: RoArmM1ServoCommandEncoder.manufacturerJointLimits.enumerated().map { commandIndex, limit in
            commandIndex == index ? limit.upperBound : 0
        })
        #expect((0...4095).contains(lowerCommand.positions[index]))
        #expect((0...4095).contains(upperCommand.positions[index]))
    }
}

@Test(.timeLimit(.minutes(1))) func roArmM1ArticulatedDynamicsPropagatesGripperMimicScalars() async throws {
    let loaded = try loadBundledRobot(relativePath: "Sources/KuyuUI/Resources/Models/RoArmM1/roarm-m1.kuyurobot.json")
    let request = ArticulatedRigidBodySimulationRequest(
        body: loaded.body,
        world: loaded.world,
        embodiment: loaded.embodiment,
        compatibilityReport: loaded.compatibilityReport,
        determinism: .tier0Strict,
        readinessLevel: .dynamicSimulation,
        duration: 0.2,
        timeStep: try TimeStep(delta: loaded.world.time.fixedStepSeconds),
        seed: ScenarioSeed(13)
    )
    let log = try await ArticulatedRigidBodySimulator().run(request: request)
    let event = try #require(log.events.last)
    let scalarByID = event.plantState.scalars

    for joint in loaded.body.joints {
        guard let mimic = joint.mimic else { continue }
        let value = try #require(scalarByID[joint.id])
        let master = try #require(scalarByID[mimic.jointID])
        assertClose(value, master * mimic.multiplier + mimic.offset)
        assertClose(try #require(scalarByID["target_\(joint.id)"]), try #require(scalarByID["target_\(mimic.jointID)"]) * mimic.multiplier + mimic.offset)
    }

    let bodyIDs = Set(event.plantState.bodies.map(\.id))
    #expect(bodyIDs.contains("l5_1_B_link"))
    #expect(bodyIDs.contains("l5_3_B_link"))
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
        for joint in loaded.body.joints where joint.mimic == nil {
            guard let value = event.plantState.scalars[joint.id] else { continue }
            if let lower = joint.lowerLimit {
                #expect(value >= lower)
            }
            if let upper = joint.upperLimit {
                #expect(value <= upper)
            }
        }
    }
}

@Test(.timeLimit(.minutes(1))) func roArmM1SmokeMotionRunsThroughMotorNerveAndStaysWithinRanges() async throws {
    let loaded = try loadBundledRobot(relativePath: "Sources/KuyuUI/Resources/Models/RoArmM1/roarm-m1.kuyurobot.json")
    let request = ArticulatedRigidBodySimulationRequest(
        body: loaded.body,
        world: loaded.world,
        embodiment: loaded.embodiment,
        compatibilityReport: loaded.compatibilityReport,
        determinism: .tier0Strict,
        readinessLevel: .dynamicSimulation,
        duration: 2.0,
        timeStep: try TimeStep(delta: loaded.world.time.fixedStepSeconds),
        seed: ScenarioSeed(7)
    )
    let log = try await ArticulatedRigidBodySimulator().run(request: request)
    let drivenJoints = loaded.body.joints.filter { $0.mimic == nil && $0.kind == .revolute }
    let actuatorSignals = loaded.embodiment.signals.actuator.sorted { $0.index < $1.index }
    let driveSignals = loaded.embodiment.signals.drive.sorted { $0.index < $1.index }
    let actuatorRangesByIndex = try rangesByIndex(actuatorSignals)
    let driveRangesByIndex = try rangesByIndex(driveSignals)
    let attachmentsByActuatorID = Dictionary(uniqueKeysWithValues: loaded.body.actuatorAttachments.map {
        ($0.actuatorID, $0)
    })
    let encoder = try RoArmM1ServoCommandEncoder(
        jointLimits: RoArmM1ServoCommandEncoder.manufacturerJointLimits
    )
    var maxAbsPositionByJointID = Dictionary(uniqueKeysWithValues: drivenJoints.map { ($0.id, 0.0) })

    #expect(log.events.isEmpty == false)
    for event in log.events {
        #expect(event.events.contains(.motorNerveUpdate))
        #expect(event.events.contains(.plantIntegrate))
        let trace = try #require(event.motorNerveTrace)
        #expect(trace.failsafeActive == false)
        #expect(trace.uRaw.count == drivenJoints.count)
        #expect(trace.uSat.count == drivenJoints.count)
        #expect(trace.uRate.count == drivenJoints.count)
        #expect(trace.uOut.count == drivenJoints.count)
        let telemetryByID = Dictionary(uniqueKeysWithValues: event.actuatorTelemetry.channels.map { ($0.id, $0.value) })

        for intent in event.driveIntents {
            let range = try #require(driveRangesByIndex[Int(intent.index.rawValue)])
            assertRangeContains(range, intent.activation)
        }

        for value in event.actuatorValues {
            let range = try #require(actuatorRangesByIndex[Int(value.index.rawValue)])
            assertRangeContains(range, value.value)
        }

        let command = try encoder.command(forActuatorValues: event.actuatorValues)
        #expect(command.t == 3)
        #expect(command.positions.count == RoArmM1ServoCommandEncoder.jointCount)
        #expect(command.positions.allSatisfy { (0...4095).contains($0) })

        for joint in drivenJoints {
            let value = try #require(event.plantState.scalars[joint.id])
            assertOptionalLowerBound(value, joint.lowerLimit)
            assertOptionalUpperBound(value, joint.upperLimit)
            maxAbsPositionByJointID[joint.id] = max(maxAbsPositionByJointID[joint.id] ?? 0.0, abs(value))
        }

        for (index, signal) in actuatorSignals.enumerated() {
            let telemetryValue = try #require(telemetryByID[signal.id])
            let jointValue = try #require(event.plantState.scalars[drivenJoints[index].id])
            let signalScalarValue = try #require(event.plantState.scalars[signal.id])
            let actuator = try #require(loaded.embodiment.actuators.first { $0.channels.contains(signal.id) })
            let attachment = try #require(attachmentsByActuatorID[actuator.id])
            let expectedActuatorPosition = actuatorPosition(
                forJointPosition: jointValue,
                commandDirection: attachment.commandDirection,
                transmissionRatio: attachment.transmissionRatio
            )
            assertClose(telemetryValue, expectedActuatorPosition)
            assertClose(signalScalarValue, expectedActuatorPosition)
        }

        for sample in event.sensorSamples {
            let index = Int(sample.channelIndex)
            guard drivenJoints.indices.contains(index) else {
                continue
            }
            let jointValue = try #require(event.plantState.scalars[drivenJoints[index].id])
            assertClose(sample.value, jointValue)
        }
    }

    for joint in drivenJoints {
        #expect((maxAbsPositionByJointID[joint.id] ?? 0.0) > 0.00001)
    }
}

private func loadBundledRobot(relativePath: String) throws -> LoadedKuyuRobot {
    let path = try packageRoot().appendingPathComponent(relativePath).path
    return try KuyuModelLoader().loadRobot(path: path)
}

private func temporaryDescriptorCorpusDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("bundled-descriptor-corpus-\(UUID().uuidString)", isDirectory: true)
}

private func descriptorCorpusEntry(
    loaded: LoadedKuyuRobot,
    entryID: String,
    label: String,
    seed: UInt64,
    hardwareReport: HardwareCalibrationReport? = nil
) throws -> DescriptorCorpusEntry {
    let timeStep = loaded.world.time.fixedStepSeconds
    return DescriptorCorpusEntry(
        loadedRobot: loaded,
        entryID: entryID,
        label: label,
        hardwareReport: hardwareReport,
        requiredReadiness: .dynamicSimulation,
        duration: timeStep * 4.0,
        timeStep: try TimeStep(delta: timeStep),
        seed: ScenarioSeed(seed),
        determinism: try DeterminismConfig(tier: .tier0)
    )
}

private func roArmM1DynamicHardwareCalibrationReport(
    loaded: LoadedKuyuRobot
) throws -> HardwareCalibrationReport {
    HardwareCalibrationReport(
        schemaVersion: "kuyu.hardware-calibration.v1",
        reportID: "bundled-roarm-m1-dynamic-calibration",
        generatedAt: "2026-06-29T00:00:00Z",
        robotID: loaded.manifest.robotID,
        bodyID: loaded.body.bodyID,
        embodimentContractID: loaded.embodiment.contractID,
        readinessLevel: .dynamicSimulation,
        positionToleranceRadians: 0.02,
        minimumSamplesPerJoint: 3,
        source: HardwareCalibrationSource(
            operatorID: "kuyu-resource-test",
            deviceID: "roarm-m1-resource-bench",
            firmwareVersion: "fixture-v0",
            measurementSystem: "resource-fixture",
            notes: "Dynamic-simulation coverage report used to prove hardware-parity gap recording."
        ),
        jointCalibrations: try activeRoArmM1DrivenJoints(body: loaded.body).map { joint in
            let attachment = try #require(loaded.body.actuatorAttachments.first { $0.jointID == joint.id })
            return JointHardwareCalibration(
                jointID: joint.id,
                actuatorID: attachment.actuatorID,
                commandDirection: attachment.commandDirection,
                mechanicalReductionRatio: attachment.mechanicalReductionRatio,
                identifiedDynamics: IdentifiedJointDynamics(
                    latencySeconds: 0.004,
                    timeConstantSeconds: 0.003,
                    deadbandRadians: 0.001,
                    backlashRadians: 0.002,
                    viscousDamping: joint.damping,
                    coulombFriction: joint.coulombFriction,
                    meanAbsoluteErrorRadians: 0.006,
                    maxObservedErrorRadians: 0.012
                ),
                samples: [
                    JointCalibrationSample(
                        commandedPositionRadians: -0.10,
                        measuredPositionRadians: -0.096,
                        commandTimeSeconds: 0.0,
                        observedTimeSeconds: 0.02
                    ),
                    JointCalibrationSample(
                        commandedPositionRadians: 0.0,
                        measuredPositionRadians: 0.001,
                        commandTimeSeconds: 0.1,
                        observedTimeSeconds: 0.12
                    ),
                    JointCalibrationSample(
                        commandedPositionRadians: 0.10,
                        measuredPositionRadians: 0.095,
                        commandTimeSeconds: 0.2,
                        observedTimeSeconds: 0.22
                    )
                ]
            )
        }
    )
}

private func activeRoArmM1DrivenJoints(body: KuyuBodyModel) -> [JointDefinition] {
    body.joints.filter { joint in
        joint.mimic == nil
            && body.actuatorAttachments.contains { $0.jointID == joint.id }
            && (joint.kind == .revolute || joint.kind == .continuous || joint.kind == .prismatic)
    }
}

private func packageRoot() throws -> URL {
    let testFileURL = URL(fileURLWithPath: #filePath)
    return testFileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func manufacturerRoArmM1URDFURL() throws -> URL {
    try packageRoot()
        .appendingPathComponent("Sources/KuyuUI/Resources/Models/RoArmM1/urdf/roarm-m1.urdf")
}

private func manufacturerRoArmM1URDF() throws -> URDFKinematicModel {
    try URDFKinematicParser().parse(url: manufacturerRoArmM1URDFURL())
}

private func kuyuVector(_ axis: Axis3) -> KuyuVector3 {
    KuyuVector3(x: axis.x, y: axis.y, z: axis.z)
}

private func jointKind(from urdfType: URDFJointType) -> JointKind {
    switch urdfType {
    case .continuous:
        return .continuous
    case .fixed, .floating, .planar:
        return .fixed
    case .prismatic:
        return .prismatic
    case .revolute:
        return .revolute
    }
}

private func jointMimic(_ mimic: URDFJointMimic) -> JointMimic {
    JointMimic(jointID: mimic.joint, multiplier: mimic.multiplier, offset: mimic.offset)
}

private func assertPoseClose(
    _ actual: KuyuPose,
    _ expected: URDFPose,
    tolerance: Double = 1e-9
) {
    assertVectorClose(actual.xyz, kuyuVector(expected.xyz), tolerance: tolerance)
    assertVectorClose(actual.rpy, kuyuVector(expected.rpy), tolerance: tolerance)
}

private func assertVectorClose(
    _ actual: KuyuVector3,
    _ expected: KuyuVector3,
    tolerance: Double = 1e-9
) {
    assertClose(actual.x, expected.x, tolerance: tolerance)
    assertClose(actual.y, expected.y, tolerance: tolerance)
    assertClose(actual.z, expected.z, tolerance: tolerance)
}

private func assertAxisClose(
    _ actual: Axis3,
    _ expected: KuyuVector3,
    tolerance: Double = 1e-9
) {
    assertClose(actual.x, expected.x, tolerance: tolerance)
    assertClose(actual.y, expected.y, tolerance: tolerance)
    assertClose(actual.z, expected.z, tolerance: tolerance)
}

private func assertOptionalClose(
    _ actual: Double?,
    _ expected: Double,
    tolerance: Double = 1e-9
) {
    guard let actual else {
        Issue.record("Expected non-nil Double")
        return
    }
    assertClose(actual, expected, tolerance: tolerance)
}

private func assertSignalRange(
    _ actual: ScalarRange?,
    equals expected: ClosedRange<Double>,
    tolerance: Double = 1e-9
) {
    guard let actual else {
        Issue.record("Expected non-nil ScalarRange")
        return
    }
    assertClose(actual.min, expected.lowerBound, tolerance: tolerance)
    assertClose(actual.max, expected.upperBound, tolerance: tolerance)
}

private func assertClose(
    _ actual: Double,
    _ expected: Double,
    tolerance: Double = 1e-9
) {
    #expect(abs(actual - expected) <= tolerance)
}

private func assertRangeContains(
    _ range: ClosedRange<Double>,
    _ value: Double,
    tolerance: Double = 1e-9
) {
    #expect(value >= range.lowerBound - tolerance)
    #expect(value <= range.upperBound + tolerance)
}

private func assertOptionalLowerBound(
    _ value: Double,
    _ lower: Double?,
    tolerance: Double = 1e-9
) {
    guard let lower else { return }
    #expect(value >= lower - tolerance)
}

private func assertOptionalUpperBound(
    _ value: Double,
    _ upper: Double?,
    tolerance: Double = 1e-9
) {
    guard let upper else { return }
    #expect(value <= upper + tolerance)
}

private func actuatorPositionRange(
    forJointRange jointRange: ClosedRange<Double>,
    commandDirection: Double,
    transmissionRatio: Double
) -> ClosedRange<Double> {
    let lower = actuatorPosition(
        forJointPosition: jointRange.lowerBound,
        commandDirection: commandDirection,
        transmissionRatio: transmissionRatio
    )
    let upper = actuatorPosition(
        forJointPosition: jointRange.upperBound,
        commandDirection: commandDirection,
        transmissionRatio: transmissionRatio
    )
    return min(lower, upper)...max(lower, upper)
}

private func actuatorPosition(
    forJointPosition jointPosition: Double,
    commandDirection: Double,
    transmissionRatio: Double
) -> Double {
    commandDirection * jointPosition * transmissionRatio
}

private func rangesByIndex(_ signals: [SignalDefinition]) throws -> [Int: ClosedRange<Double>] {
    var ranges: [Int: ClosedRange<Double>] = [:]
    for signal in signals {
        let range = try #require(signal.range)
        ranges[signal.index] = range.min...range.max
    }
    return ranges
}

private extension String {
    var lastPathComponentAfterSlash: String {
        split(separator: "/").last.map(String.init) ?? self
    }
}
