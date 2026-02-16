import Testing
import Foundation
import KuyuPhysics
import KuyuScenarios

@Test func runtimeInteroperabilityDescriptorExportsCapabilityFields() throws {
    let base = try loadBundledDescriptor(relativePath: "Sources/KuyuUI/Resources/Models/QuadRef/quadref.model.json").descriptor
    let descriptor = RobotDescriptor(
        robot: base.robot,
        physics: base.physics,
        render: base.render,
        signals: base.signals,
        sensors: base.sensors,
        actuators: base.actuators,
        control: RobotDescriptor.Control(
            driveChannels: base.control.driveChannels,
            reflexChannels: base.control.reflexChannels,
            descendingChannels: base.control.descendingChannels,
            summaryChannels: base.control.summaryChannels,
            constraints: base.control.constraints,
            latencyBudgetsMs: RobotDescriptor.LatencyBudgetsMs(
                reflexPathBudgetMs: 2.0,
                corePathBudgetMs: 8.0,
                descendingApplyBudgetMs: 8.0,
                summaryExportBudgetMs: 20.0
            )
        ),
        observation: base.observation,
        motorNerve: base.motorNerve
    )
    let capability = RuntimeCapabilitySnapshot(descriptor: descriptor)

    #expect(!capability.sensorSet.isEmpty)
    #expect(!capability.actuatorLimits.isEmpty)
    #expect(!capability.updateRates.isEmpty)
    #expect(capability.latencyBudgets != nil)
}

@Test func runtimeInteroperabilityNegotiationRejectsMissingLatencyBudgetsWhenRequired() throws {
    let descriptor = try loadBundledDescriptor(relativePath: "Sources/KuyuUI/Resources/Models/SingleProp/singleprop.model.json").descriptor
    let capability = RuntimeCapabilitySnapshot(descriptor: descriptor)

    do {
        _ = try capability.negotiate(RuntimeCapabilityRequest(requireLatencyBudgets: true))
        #expect(Bool(false))
    } catch let error as RuntimeNegotiationError {
        #expect(error == .missingLatencyBudgets)
    }
}

@Test func runtimeInteroperabilityNegotiationValidatesSensorAndRateRequirements() throws {
    let descriptor = try loadBundledDescriptor(relativePath: "Sources/KuyuUI/Resources/Models/QuadRef/quadref.model.json").descriptor
    let capability = RuntimeCapabilitySnapshot(descriptor: descriptor)
    let request = RuntimeCapabilityRequest(
        requiredSensors: ["imu6"],
        requiredActuatorIDs: ["motor_set"],
        minimumRates: ["sensor:imu6": 100.0]
    )

    let result = try capability.negotiate(request)
    #expect(result.snapshot.sensorSet.contains("imu6"))
}

private func loadBundledDescriptor(relativePath: String) throws -> LoadedRobotDescriptor {
    let testFileURL = URL(fileURLWithPath: #filePath)
    let packageRoot = testFileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let descriptorPath = packageRoot.appendingPathComponent(relativePath).path
    return try RobotDescriptorLoader().loadDescriptor(path: descriptorPath)
}
