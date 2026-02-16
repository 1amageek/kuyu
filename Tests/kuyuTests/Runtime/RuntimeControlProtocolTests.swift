import Foundation
import Testing
import Logging
import KuyuPhysics
import KuyuScenarios

@Test func runtimeControlProtocolStartsSessionOnSimulationAdapter() throws {
    let base = try loadBundledDescriptor(relativePath: "Sources/KuyuUI/Resources/Models/QuadRef/quadref.model.json").descriptor
    let descriptor = descriptorWithLatencyBudgets(base)
    let adapter = SimulationRuntimeAdapter(
        adapterID: "sim-main",
        transport: .inProcess,
        descriptor: descriptor
    )
    let request = RuntimeSessionStartRequest(
        capabilityRequest: RuntimeCapabilityRequest(
            requiredSensors: ["imu6"],
            requiredActuatorIDs: ["motor_set"],
            minimumRates: ["sensor:imu6": 100.0],
            requireLatencyBudgets: true
        ),
        enforceReflexPathLowLatency: true
    )
    var events: [RuntimeSessionEvent] = []
    let session = try RuntimeSessionCoordinator.startSession(
        adapter: adapter,
        request: request,
        logger: Logger(label: "kuyu.runtime.test"),
        eventSink: { events.append($0) }
    )
    #expect(session.backendKind == .simulation)
    #expect(session.transport == .inProcess)
    #expect(events.map(\.code) == [
        "session.start",
        "session.negotiation_ok",
        "session.latency_policy_ok",
        "session.ready"
    ])
}

@Test func runtimeControlProtocolStartsSessionOnRobotAdapter() throws {
    let base = try loadBundledDescriptor(relativePath: "Sources/KuyuUI/Resources/Models/QuadRef/quadref.model.json").descriptor
    let descriptor = descriptorWithLatencyBudgets(base)
    let adapter = MockRuntimeAdapter(
        adapterID: "robot-shm",
        backendKind: .robot,
        transport: .sharedMemory,
        capabilitySnapshot: RuntimeCapabilitySnapshot(descriptor: descriptor)
    )
    let request = RuntimeSessionStartRequest(
        capabilityRequest: RuntimeCapabilityRequest(requireLatencyBudgets: true),
        enforceReflexPathLowLatency: true
    )

    let session = try RuntimeSessionCoordinator.startSession(adapter: adapter, request: request)
    #expect(session.backendKind == .robot)
    #expect(session.transport == .sharedMemory)
}

@Test func runtimeControlProtocolRejectsHighLatencyTransportWhenReflexBudgetIsEnforced() throws {
    let base = try loadBundledDescriptor(relativePath: "Sources/KuyuUI/Resources/Models/QuadRef/quadref.model.json").descriptor
    let descriptor = descriptorWithLatencyBudgets(base)
    let adapter = MockRuntimeAdapter(
        adapterID: "robot-grpc",
        backendKind: .robot,
        transport: .grpc,
        capabilitySnapshot: RuntimeCapabilitySnapshot(descriptor: descriptor)
    )
    let request = RuntimeSessionStartRequest(
        capabilityRequest: RuntimeCapabilityRequest(requireLatencyBudgets: true),
        enforceReflexPathLowLatency: true
    )
    var events: [RuntimeSessionEvent] = []

    do {
        _ = try RuntimeSessionCoordinator.startSession(
            adapter: adapter,
            request: request,
            logger: Logger(label: "kuyu.runtime.test"),
            eventSink: { events.append($0) }
        )
        #expect(Bool(false))
    } catch let error as RuntimeSessionError {
        #expect(error == .reflexLatencyRequiresLowLatencyTransport(.grpc))
        #expect(events.map(\.code) == [
            "session.start",
            "session.negotiation_ok",
            "session.latency_policy_rejected"
        ])
    }
}

private struct MockRuntimeAdapter: RuntimeControlAdapter {
    let adapterID: String
    let backendKind: RuntimeBackendKind
    let transport: RuntimeTransportKind
    let capabilitySnapshot: RuntimeCapabilitySnapshot
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

private func descriptorWithLatencyBudgets(_ base: RobotDescriptor) -> RobotDescriptor {
    RobotDescriptor(
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
}
