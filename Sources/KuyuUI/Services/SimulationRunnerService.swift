import KuyuCore
import KuyuMLX

@MainActor
struct SimulationRunnerService {
    let modelStore: ManasMLXModelStore

    init(modelStore: ManasMLXModelStore) {
        self.modelStore = modelStore
    }

    func run(request: SimulationRunRequest, control: SimulationControl? = nil) async throws -> KuyAtt1RunOutput {
        let schedule = try SimulationSchedule.baseline(cutPeriodSteps: request.cutPeriodSteps)
        let parameters = loadParameters(request: request)
        switch request.controller {
        case .baseline:
            let runner = KuyAtt1Runner(
                parameters: parameters,
                schedule: schedule,
                determinism: request.determinism,
                noise: request.noise,
                gains: request.gains
            )
            return try await runner.runWithLogs(control: control)
        case .manasMLX:
            return try await modelStore.runManasMLX(
                parameters: parameters,
                schedule: schedule,
                request: request,
                control: control
            )
        }
    }

    private func loadParameters(request: SimulationRunRequest) -> QuadrotorParameters {
        if let override = request.overrideParameters {
            return override
        }

        let descriptorPath = request.modelDescriptorPath
        let trimmed = descriptorPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .baseline
        }

        do {
            let loader = RobotModelLoader()
            let loaded = try loader.loadDescriptor(path: trimmed)
            return try loader.loadQuadrotorParameters(descriptor: loaded)
        } catch {
            return .baseline
        }
    }

 
}
