import Foundation
import KuyuScenarios

@MainActor
public extension SimulationViewModel {
    static func makeRoArmM1SimulationPreviewModel() -> SimulationViewModel {
        let model = SimulationViewModel(logStore: UILogStore(buffer: UILogBuffer()))
        model.configureRoArmM1SimulationPreview()
        return model
    }

    func configureRoArmM1SimulationPreview() {
        setRobotManifestPath(
            KuyuUIModelPaths.defaultRoArmM1RobotManifestPath(),
            source: "roarm-m1-simulator-preview"
        )
        useRenderAssets = true
        controllerSelection = .teacherBaseline
        determinismSelection = .tier0
        taskMode = .lift
    }

    func startRoArmM1SimulationPreview() {
        configureRoArmM1SimulationPreview()
        guard !isRunning, !isLoopRunning else { return }
        runBaseline()
    }

    func runRoArmM1SimulationPreviewPlaybackLoop() async {
        while !Task.isCancelled {
            while !Task.isCancelled && (isRunning || selectedScenario == nil) {
                guard await sleepRoArmM1PreviewFrame(nanoseconds: 100_000_000) else { return }
            }

            guard !Task.isCancelled else { return }
            let timeRange = selectedScenario?.metrics.timeRange ?? 0...6
            let duration = max(timeRange.upperBound - timeRange.lowerBound, 0.1)
            let startDate = Date()

            while !Task.isCancelled && !isRunning {
                let elapsed = Date().timeIntervalSince(startDate)
                simulationPlaybackFraction = elapsed.truncatingRemainder(dividingBy: duration) / duration
                guard await sleepRoArmM1PreviewFrame(nanoseconds: 33_333_333) else { return }
            }
        }
    }

    private func sleepRoArmM1PreviewFrame(nanoseconds: UInt64) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: nanoseconds)
            return true
        } catch {
            return false
        }
    }
}
