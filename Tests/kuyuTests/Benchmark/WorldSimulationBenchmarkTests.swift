import Foundation
import Testing

@testable import KuyuCore

private struct HoverCut: CutInterface {
    let hoverThrust: Double

    init(hoverThrust: Double) {
        self.hoverThrust = hoverThrust
    }

    mutating func update(samples: [ChannelSample], time: WorldTime) throws -> CutOutput {
        let commands = try [
            ActuatorCommand(index: ActuatorIndex(0), value: hoverThrust),
            ActuatorCommand(index: ActuatorIndex(1), value: hoverThrust),
            ActuatorCommand(index: ActuatorIndex(2), value: hoverThrust),
            ActuatorCommand(index: ActuatorIndex(3), value: hoverThrust),
        ]
        return .actuatorCommands(commands)
    }
}

@Test("World simulation benchmark")
func worldSimulationBenchmark() async {
    do {
        let timeStep = try TimeStep(delta: 0.001)
        let schedule = SimulationSchedule(
            sensor: try SubsystemSchedule(periodSteps: 1),
            actuator: try SubsystemSchedule(periodSteps: 1),
            cut: try SubsystemSchedule(periodSteps: 1)
        )
        let determinism = try DeterminismConfig(tier: .tier1, tier1Tolerance: .baseline)
        let parameters = QuadrotorParameters.baseline
        let environment = try WorldEnvironment(
            gravity: parameters.gravity,
            windVelocityWorld: Axis3(x: 5.0, y: 0.0, z: 0.0),
            airPressure: 101_325.0,
            airTemperature: 288.15,
            usage: .full
        )
        let runner = ScenarioRunner<HoverCut, UnusedExternalDAL>(
            parameters: parameters,
            schedule: schedule,
            determinism: determinism,
            environment: environment
        )
        let config = try ScenarioConfig(
            id: ScenarioID("bench-hover"),
            seed: ScenarioSeed(1001),
            duration: 5.0,
            timeStep: timeStep
        )
        let envelope = try SafetyEnvelope(
            omegaSafeMax: 20.0,
            tiltSafeMaxDegrees: 60.0,
            sustainedViolationSeconds: 0.2
        )
        let scenario = ScenarioDefinition(
            config: config,
            kind: .hoverStart,
            initialAttitude: EulerAngles.degrees(roll: 5, pitch: 0, yaw: 0),
            initialAngularVelocity: Axis3(x: 0, y: 0, z: 0),
            safetyEnvelope: envelope,
            torqueEvents: [],
            actuatorDegradation: nil,
            gyroDriftScale: 1.0,
            swapEvents: [],
            hfEvents: []
        )
        let hoverThrust = parameters.mass * parameters.gravity / 4.0
        let repetitions = 100

        let clock = ContinuousClock()
        let start = clock.now
        for _ in 0..<repetitions {
            _ = try await runner.runScenario(definition: scenario, cut: HoverCut(hoverThrust: hoverThrust))
        }
        let end = clock.now
        let elapsed = end - start
        let components = elapsed.components
        let seconds = Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000.0

        let stepsPerRun = Int((config.duration / timeStep.delta).rounded(.down))
        let totalSteps = stepsPerRun * repetitions
        let stepsPerSecond = seconds > 0 ? Double(totalSteps) / seconds : 0
        let simSeconds = config.duration * Double(repetitions)
        let realtimeFactor = seconds > 0 ? simSeconds / seconds : 0

        print("[Benchmark] steps=\(totalSteps) elapsed=\(String(format: "%.6f", seconds))s steps/s=\(String(format: "%.1f", stepsPerSecond)) simRealtime=\(String(format: "%.2f", realtimeFactor))x")
        #expect(totalSteps > 0)
    } catch {
        print("[Benchmark] failed: \(error)")
        #expect(Bool(false), "Benchmark failed: \(error)")
    }
}
