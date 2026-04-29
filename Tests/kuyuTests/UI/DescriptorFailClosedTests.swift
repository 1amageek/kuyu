import Foundation
import Testing
import KuyuCore
import KuyuMLX
import KuyuPhysics
import KuyuScenarios
@testable import KuyuUI

@MainActor
@Test(.timeLimit(.minutes(1))) func uiModelPathResolutionPreservesMissingCustomDescriptorPath() throws {
    let missing = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-missing-\(UUID().uuidString).json")
        .path

    #expect(!FileManager.default.fileExists(atPath: missing))
    #expect(KuyuUIModelPaths.resolveDescriptorPath(missing) == missing)
}

@MainActor
@Test(.timeLimit(.minutes(1))) func simulationRunnerRejectsInvalidDescriptorInsteadOfFallingBackToBaseline() async throws {
    let missing = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-missing-\(UUID().uuidString).json")
        .path
    let request = SimulationRunRequest(
        controller: .teacherBaseline,
        taskMode: .singleLift,
        gains: try ImuRateDampingCutGains(kp: 2.0, kd: 0.25, yawDamping: 0.2, hoverThrustScale: 1.0),
        cutPeriodSteps: 2,
        noise: .zero,
        determinism: .tier1Baseline,
        modelDescriptorPath: missing,
        overrideParameters: nil,
        useAux: true,
        useQualityGating: true
    )
    let service = SimulationRunnerService(modelStore: ManasMLXModelStore())

    do {
        _ = try await service.run(request: request)
        Issue.record("Expected invalid descriptor path to fail instead of using baseline parameters")
    } catch let error as RobotDescriptorLoader.LoaderError {
        switch error {
        case .descriptorReadFailed, .descriptorNotFound:
            break
        default:
            Issue.record("Unexpected descriptor loader error: \(error)")
        }
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@MainActor
@Test(.timeLimit(.minutes(1))) func simulationViewModelStopsRunWhenModelPreflightFails() throws {
    let missing = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-missing-\(UUID().uuidString).json")
        .path
    let model = makeSimulationViewModel()

    model.controllerSelection = .teacherBaseline
    model.taskMode = .singleLift
    model.setModelDescriptorPath(missing, source: "test")
    model.runBaseline()

    #expect(model.isRunning == false)
    #expect(model.runs.isEmpty)
    #expect(model.runError?.contains("Model preflight failed") == true)
    #expect(model.runError?.contains(missing) == true)
}

@MainActor
@Test(.timeLimit(.minutes(1))) func simulationViewModelStopsTrainingLoopWhenModelPreflightFails() throws {
    let missing = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-missing-\(UUID().uuidString).json")
        .path
    let model = makeSimulationViewModel()

    model.controllerSelection = .manasMLX
    model.taskMode = .singleLift
    model.setModelDescriptorPath(missing, source: "test")
    model.startTrainingLoop()

    #expect(model.isLoopRunning == false)
    #expect(model.loopStatusMessage.isEmpty)
    #expect(model.runError?.contains("Model preflight failed") == true)
    #expect(model.runError?.contains(missing) == true)
}

@MainActor
@Test(.timeLimit(.minutes(1))) func uiActionLogsIncludeRequiredContextForDescriptorAndPreflightFailure() async throws {
    let missing = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-missing-\(UUID().uuidString).json")
        .path
    let (model, store) = makeSimulationViewModelWithStore()

    model.controllerSelection = .teacherBaseline
    model.taskMode = .singleLift
    model.setModelDescriptorPath(missing, source: "test")
    model.runBaseline()

    let uiEntries = try await waitForUIEntries(store: store) { entries in
        entries.contains { entry in
            entry.metadata["action"] == "setDescriptorPath"
                && entry.metadata["task"] == SimulationTaskMode.singleLift.rawValue
                && entry.metadata["modelDescriptor"] == missing
        } && entries.contains { entry in
            entry.metadata["action"] == "modelPreflight"
                && entry.metadata["reason"] == "loadFailed"
                && entry.metadata["modelDescriptor"] == missing
        }
    }
    #expect(uiEntries.contains { entry in
        entry.metadata["action"] == "setDescriptorPath"
            && entry.metadata["task"] == SimulationTaskMode.singleLift.rawValue
            && entry.metadata["modelDescriptor"] == missing
    })
    #expect(uiEntries.contains { entry in
        entry.metadata["action"] == "modelPreflight"
            && entry.metadata["reason"] == "loadFailed"
            && entry.metadata["modelDescriptor"] == missing
    })
}

@MainActor
private func makeSimulationViewModel() -> SimulationViewModel {
    makeSimulationViewModelWithStore().model
}

@MainActor
private func makeSimulationViewModelWithStore() -> (model: SimulationViewModel, store: UILogStore) {
    let buffer = UILogBuffer()
    let store = UILogStore(buffer: buffer)
    return (SimulationViewModel(logStore: store), store)
}

@MainActor
private func waitForUIEntries(
    store: UILogStore,
    matching predicate: ([UILogEntry]) -> Bool
) async throws -> [UILogEntry] {
    for _ in 0..<40 {
        let entries = store.entries.filter { $0.label == "kuyu.ui" }
        if predicate(entries) {
            return entries
        }
        try await Task.sleep(for: .milliseconds(25))
    }
    return store.entries.filter { $0.label == "kuyu.ui" }
}
