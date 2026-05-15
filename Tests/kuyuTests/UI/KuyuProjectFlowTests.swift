import Foundation
import KuyuMLX
import KuyuTraining
import Testing
@testable import KuyuUI

@MainActor
@Test(.timeLimit(.minutes(1))) func appViewModelCreatesAndOpensDesignOnlyKuyuProject() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-project-flow-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer {
        removeTemporaryDirectory(root)
    }

    let model = AppViewModel(logStore: UILogStore(buffer: UILogBuffer()))
    model.createProject(
        name: "GroundRobot",
        parentDirectory: root,
        template: LearningProjectTemplate.groundRobotPointNavigation
    )
    await model.waitForProjectCreation()

    let projectURL = root
        .appendingPathComponent("GroundRobot", isDirectory: true)
        .appendingPathExtension("kuyu")

    #expect(model.currentProject?.package.rootURL == projectURL)
    #expect(model.currentProject?.package.manifest.name == "GroundRobot")
    #expect(model.currentProject?.isRunnable == false)
    #expect(model.projectCreationError == nil)
    #expect(FileManager.default.fileExists(atPath: projectURL.appendingPathComponent("project.json").path))
    #expect(FileManager.default.fileExists(atPath: projectURL.appendingPathComponent("experiments/default/experiment.json").path))
    #expect(FileManager.default.fileExists(atPath: projectURL.appendingPathComponent("model-bundles/source.bundle-ref.json").path))
}

@MainActor
@Test(.timeLimit(.minutes(1))) func appViewModelRestoresRecentProjectsForWelcomeWindow() async throws {
    let suiteName = "team.stamp.Bounded.tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }

    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-project-recent-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer {
        removeTemporaryDirectory(root)
    }

    let model = AppViewModel(
        logStore: UILogStore(buffer: UILogBuffer()),
        recentProjectsDefaults: defaults
    )
    model.createProject(
        name: "RecentRobot",
        parentDirectory: root,
        template: LearningProjectTemplate.groundRobotPointNavigation
    )
    await model.waitForProjectCreation()

    let projectURL = root
        .appendingPathComponent("RecentRobot", isDirectory: true)
        .appendingPathExtension("kuyu")
        .standardizedFileURL

    let relaunchedModel = AppViewModel(
        logStore: UILogStore(buffer: UILogBuffer()),
        recentProjectsDefaults: defaults
    )
    #expect(relaunchedModel.recentProjectURLs.first == projectURL)
}

@MainActor
@Test(.timeLimit(.minutes(1))) func appViewModelIgnoresLegacyPathOnlyRecentProjects() async throws {
    let suiteName = "team.stamp.Bounded.tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }

    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-project-legacy-recent-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer {
        removeTemporaryDirectory(root)
    }

    let projectURL = root
        .appendingPathComponent("LegacyRobot", isDirectory: true)
        .appendingPathExtension("kuyu")
        .standardizedFileURL
    let package = try KuyuProjectFactory().makeRunnableStarterProject(
        rootURL: projectURL,
        name: "LegacyRobot",
        template: .groundRobotPointNavigation
    )
    try KuyuProjectPackageWriter().write(package)
    defaults.set([projectURL.path], forKey: "team.stamp.Bounded.recentProjectPaths")

    let model = AppViewModel(
        logStore: UILogStore(buffer: UILogBuffer()),
        recentProjectsDefaults: defaults
    )
    #expect(model.recentProjectURLs.isEmpty)
}

@MainActor
@Test(.timeLimit(.minutes(1))) func appViewModelRejectsRunnableProjectMissingSourceBundle() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-project-missing-bundle-\(UUID().uuidString)", isDirectory: true)
    let projectURL = root
        .appendingPathComponent("Drone", isDirectory: true)
        .appendingPathExtension("kuyu")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer {
        removeTemporaryDirectory(root)
    }

    let package = try KuyuProjectFactory().makeRunnableStarterProject(
        rootURL: projectURL,
        name: "Drone",
        template: .droneAutonomyStarter
    )
    try KuyuProjectPackageWriter().write(package)

    let model = AppViewModel(logStore: UILogStore(buffer: UILogBuffer()))
    model.openProject(at: projectURL)

    #expect(model.currentProject == nil)
    #expect(model.projectCreationError?.contains("Missing source model bundle") == true)
}

@MainActor
@Test(.timeLimit(.minutes(1))) func droneStarterProjectOpensWithFoundationSuiteDefaults() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-project-foundation-defaults-\(UUID().uuidString)", isDirectory: true)
        .appendingPathExtension("kuyu")
    defer {
        removeTemporaryDirectory(root)
    }
    let package = try KuyuProjectFactory().makeRunnableStarterProject(
        rootURL: root,
        name: "Drone",
        template: .droneAutonomyStarter
    )
    let model = AppViewModel(logStore: UILogStore(buffer: UILogBuffer()))

    model.simulationViewModel.configureForProjectPackage(package)

    #expect(model.simulationViewModel.learningCampaignSuites == "6")
    #expect(model.simulationViewModel.learningCampaignSeedCount == 2)
    #expect(model.simulationViewModel.learningCampaignPopulation == 100)
    #expect(model.simulationViewModel.learningCampaignGenerations >= 1_000)
}

@MainActor
@Test(.timeLimit(.minutes(1))) func projectOpenLoadsLatestRunForCheckpointContinuation() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-project-resume-\(UUID().uuidString)", isDirectory: true)
        .appendingPathExtension("kuyu")
    defer {
        removeTemporaryDirectory(root)
    }
    let package = try KuyuProjectFactory().makeRunnableStarterProject(
        rootURL: root,
        name: "Drone",
        template: .droneAutonomyStarter
    )
    let checkpoint = root
        .appendingPathComponent("model-bundles", isDirectory: true)
        .appendingPathComponent("accepted.manasbundle", isDirectory: true)
    try writeCompleteCheckpointSkeleton(at: checkpoint)
    let candidateCheckpoint = root
        .appendingPathComponent("runs", isDirectory: true)
        .appendingPathComponent("run-100", isDirectory: true)
        .appendingPathComponent("seeds", isDirectory: true)
        .appendingPathComponent("seed-1", isDirectory: true)
        .appendingPathComponent("evolution", isDirectory: true)
        .appendingPathComponent("candidates", isDirectory: true)
        .appendingPathComponent("generation-12", isDirectory: true)
        .appendingPathComponent("candidate-3", isDirectory: true)
    try writeCompleteCheckpointSkeleton(at: candidateCheckpoint)

    let run = root
        .appendingPathComponent("runs", isDirectory: true)
        .appendingPathComponent("run-100", isDirectory: true)
    try FileManager.default.createDirectory(at: run, withIntermediateDirectories: true)
    try writeJSON(
        makeProjectFlowContinuationPlan(root: run, task: "lift"),
        to: run.appendingPathComponent("learning-campaign-plan.json")
    )
    let summary = LearningCampaignSummary(
        artifactRoot: run.path,
        seedCount: 1,
        acceptedCount: 1,
        finalCheckpoint: checkpoint.path,
        runs: []
    )
    let status = LearningCampaignStatus(
        status: "cancelled",
        exitCode: 130,
        startedAt: "2026-05-10T00:00:00Z",
        finishedAt: "2026-05-10T00:01:00Z"
    )
    try writeJSON(summary, to: run.appendingPathComponent("learning-campaign-summary.json"))
    try writeJSON(status, to: run.appendingPathComponent("campaign-status.json"))
    let evolution = run
        .appendingPathComponent("seeds", isDirectory: true)
        .appendingPathComponent("seed-1", isDirectory: true)
        .appendingPathComponent("evolution", isDirectory: true)
    try FileManager.default.createDirectory(at: evolution, withIntermediateDirectories: true)
    try writeJSONLines([
        GenomeCandidate(
            runID: "resume-run",
            generationIndex: 12,
            candidateID: "g12-c3",
            genomeID: "resume-run-g12-c3",
            checkpointID: "g12-c3",
            checkpointURL: candidateCheckpoint,
            mutationRate: 0.08,
            mutationNoiseScale: 0.01,
            mutationSummary: "gaussian-crossover-mutation"
        )
    ], to: evolution.appendingPathComponent("candidates.jsonl"))
    try writeJSONLines([
        FitnessSummary(
            runID: "resume-run",
            generationIndex: 12,
            candidateID: "g12-c3",
            taskID: "lift",
            scalarFitness: 42,
            rewardAverage: -10,
            taskPassRate: 0,
            safetyViolationRate: 1,
            holdTimeRatio: 0,
            altitudeErrorRatio: 1
        )
    ], to: evolution.appendingPathComponent("fitness.jsonl"))

    let model = AppViewModel(logStore: UILogStore(buffer: UILogBuffer()))
    model.simulationViewModel.configureForProjectPackage(package)
    await model.simulationViewModel.waitForLearningCampaignArtifactLoad()

    #expect(URL(fileURLWithPath: model.simulationViewModel.learningCampaignArtifactDirectory).standardizedFileURL == run.standardizedFileURL)
    #expect(model.simulationViewModel.learningCampaignState?.finalCheckpoint == checkpoint.path)
    #expect(model.simulationViewModel.canContinueLearningCampaign)
    #expect(model.simulationViewModel.learningCampaignContinuationCheckpointPath == candidateCheckpoint.path)
    #expect(!model.simulationViewModel.isLearningCampaignRunning)
}

private func removeTemporaryDirectory(_ url: URL) {
    guard FileManager.default.fileExists(atPath: url.path) else {
        return
    }
    do {
        try FileManager.default.removeItem(at: url)
    } catch {
        Issue.record("Temporary directory cleanup failed: \(error)")
    }
}

private func writeCompleteCheckpointSkeleton(at url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: url.appendingPathComponent("model.json"), options: [.atomic])
    try Data("core".utf8).write(to: url.appendingPathComponent("core.safetensors"), options: [.atomic])
    try Data("reflex".utf8).write(to: url.appendingPathComponent("reflex.safetensors"), options: [.atomic])
    try Data(SelfContainedContinuationBundleManifest.fixtureJSON.utf8).write(
        to: url.appendingPathComponent("manas-bundle.json"),
        options: [.atomic]
    )
}

private enum SelfContainedContinuationBundleManifest {
    static let fixtureJSON = """
    {
      "bundleID" : "fixture",
      "components" : [
        {
          "contentType" : "application/json",
          "path" : "model.json",
          "required" : true,
          "role" : "modelConfig"
        },
        {
          "contentType" : "application/vnd.safetensors",
          "path" : "core.safetensors",
          "required" : true,
          "role" : "coreWeights"
        },
        {
          "contentType" : "application/vnd.safetensors",
          "path" : "reflex.safetensors",
          "required" : true,
          "role" : "reflexWeights"
        }
      ],
      "createdAt" : "1970-01-01T00:00:00Z",
      "modelFamily" : "manas",
      "runtimeContract" : {
        "configHash" : "config",
        "descriptorHash" : "descriptor",
        "driveSemanticsID" : "drive",
        "observationSchemaID" : "observation"
      },
      "schemaVersion" : 1
    }
    """
}

private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    try data.write(to: url, options: .atomic)
}

private func writeJSONLines<T: Encodable>(_ values: [T], to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let lines = try values.map { value in
        let data = try encoder.encode(value)
        guard let line = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(value, EncodingError.Context(
                codingPath: [],
                debugDescription: "JSON line could not be represented as UTF-8."
            ))
        }
        return line
    }
    try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
}

private func makeProjectFlowContinuationPlan(root: URL, task: String) -> LearningCampaignPlan {
    LearningCampaignPlan(
        artifactRoot: root.path,
        task: task,
        trainingStageID: "evolution-search",
        trainingStageDisplayName: "Evolution Search",
        trainingStageKind: .evolution,
        suites: ["6"],
        episodes: 1,
        workers: 1,
        population: 100,
        generations: 1_000,
        eliteCount: 10,
        candidateEvaluationConcurrency: 100,
        seeds: ["1"],
        sourceCheckpoint: nil,
        modelDescriptor: nil,
        variation: "gaussian",
        searchStrategy: "qualityDiversity",
        mutationRate: 0.14,
        mutationNoiseScale: 0.025,
        bootstrapSuite: "6",
        bootstrapEpisodes: 0,
        bootstrapSequence: 0,
        bootstrapEpochs: 0,
        bootstrapMaxBatches: 0,
        bootstrapLearningRate: 0,
        bootstrapRepairAttempts: nil,
        verifyParentTask: true,
        resumeEnabled: false,
        resourceSampleSeconds: 0,
        artifactRetentionPolicy: .compact,
        availableDiskBytes: 1_000_000_000,
        requiredDiskBytes: 1,
        plannedCandidateEvaluations: 100_000,
        plannedRegressionRollouts: 100_000,
        plannedRegressionEpisodes: 100_000,
        autonomousPipeline: AutonomousTrainingPipelineFactory().defaultPlan(
            domain: .aerialDrone,
            taskProfileIDs: ["lift-v1"]
        ),
        convergence: LearningCampaignConvergencePlan(
            earlyStoppingEnabled: true,
            patienceGenerations: 50,
            minimumFitnessImprovement: 0.001,
            minimumTaskPassRateImprovement: 0.001,
            minimumHoldTimeRatioImprovement: 0.001
        )
    )
}
