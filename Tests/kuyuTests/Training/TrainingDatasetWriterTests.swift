import Foundation
import Testing
@testable import KuyuCore

@Test(.timeLimit(.minutes(1))) func trainingDatasetWriterExportsMetaAndRecords() async throws {
    let log = try makeLog()
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)

    let writer = TrainingDatasetWriter()
    let output = try writer.write(log: log, to: directory)

    let metaURL = output.appendingPathComponent("meta.json")
    let recordsURL = output.appendingPathComponent("records.jsonl")

    #expect(FileManager.default.fileExists(atPath: metaURL.path))
    #expect(FileManager.default.fileExists(atPath: recordsURL.path))

    let metaData = try Data(contentsOf: metaURL)
    let meta = try JSONDecoder().decode(TrainingDatasetMetadata.self, from: metaData)
    #expect(meta.recordCount == log.events.count)
    #expect(meta.driveCount == 2)
    #expect(meta.channelCount == 1)

    let recordLines = try String(contentsOf: recordsURL, encoding: .utf8)
        .split(separator: "\n")
    #expect(recordLines.count == log.events.count)

    let first = try JSONDecoder().decode(TrainingDatasetRecord.self, from: Data(recordLines[0].utf8))
    #expect(first.sensors.count == 1)
    #expect(first.driveIntents.count == 1)
    #expect(first.reflexCorrections.count == 1)
}

private func makeLog() throws -> SimulationLog {
    let scenarioId = try ScenarioID("TRAIN")
    let seed = ScenarioSeed(42)
    let timeStep = try TimeStep(delta: 0.01)

    let sample = try ChannelSample(channelIndex: 0, value: 0.5, timestamp: 0.0)
    let drive = try DriveIntent(index: DriveIndex(0), activation: 0.2)
    let reflex = try ReflexCorrection(
        driveIndex: DriveIndex(0),
        clampMultiplier: 0.9,
        damping: 0.1,
        delta: 0.0
    )

    let snapshot = QuadrotorStateSnapshot(
        position: Axis3(x: 0, y: 0, z: 0),
        velocity: Axis3(x: 0, y: 0, z: 0),
        orientation: QuaternionSnapshot(w: 1, x: 0, y: 0, z: 0),
        angularVelocity: Axis3(x: 0, y: 0, z: 0)
    )

    let step0 = WorldStepLog(
        time: try WorldTime(stepIndex: 0, time: 0.0),
        events: [.timeAdvance, .logging],
        sensorSamples: [sample],
        driveIntents: [drive],
        reflexCorrections: [reflex],
        actuatorCommands: [],
        motorThrusts: try MotorThrusts.uniform(0.0),
        safetyTrace: SafetyTrace(omegaMagnitude: 0, tiltRadians: 0),
        stateSnapshot: snapshot,
        disturbanceTorqueBody: Axis3(x: 0, y: 0, z: 0),
        disturbanceForceWorld: Axis3(x: 0, y: 0, z: 0)
    )

    let step1 = WorldStepLog(
        time: try WorldTime(stepIndex: 1, time: 0.01),
        events: [.timeAdvance, .logging],
        sensorSamples: [sample],
        driveIntents: [drive],
        reflexCorrections: [reflex],
        actuatorCommands: [],
        motorThrusts: try MotorThrusts.uniform(0.0),
        safetyTrace: SafetyTrace(omegaMagnitude: 0, tiltRadians: 0),
        stateSnapshot: snapshot,
        disturbanceTorqueBody: Axis3(x: 0, y: 0, z: 0),
        disturbanceForceWorld: Axis3(x: 0, y: 0, z: 0)
    )

    return SimulationLog(
        scenarioId: scenarioId,
        seed: seed,
        timeStep: timeStep,
        determinism: try DeterminismConfig(tier: .tier1, tier1Tolerance: .baseline),
        configHash: "train",
        events: [step0, step1]
    )
}

@Test(.timeLimit(.minutes(1))) func trainingDatasetExporterWritesPerScenario() async throws {
    let log = try makeLog()
    let entry = ScenarioLogEntry(key: ScenarioKey(scenarioId: log.scenarioId, seed: log.seed), log: log)
    let output = KuyAtt1RunOutput(
        result: SuiteRunResult(evaluations: [], replayChecks: [], passed: true),
        summary: ValidationSummary(suitePassed: true, evaluations: [], replayChecks: [], manifest: [], aggregate: EvaluationAggregate(averageRecoveryTime: nil, worstOvershootDegrees: nil, averageHfStabilityScore: nil)),
        logs: [entry]
    )

    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)

    let exporter = TrainingDatasetExporter()
    let outputs = try exporter.write(output: output, to: directory)

    #expect(outputs.count == 1)
    let exportURL = outputs[entry.key]
    #expect(exportURL != nil)
    if let exportURL {
        #expect(FileManager.default.fileExists(atPath: exportURL.appendingPathComponent("meta.json").path))
        #expect(FileManager.default.fileExists(atPath: exportURL.appendingPathComponent("records.jsonl").path))
    }
}
