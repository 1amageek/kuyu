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
@Test(.timeLimit(.minutes(1))) func appViewModelDoesNotCreateHiddenProjectPackagesFromDottedNames() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-project-hidden-name-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer {
        removeTemporaryDirectory(root)
    }

    let model = AppViewModel(logStore: UILogStore(buffer: UILogBuffer()))
    model.createProject(
        name: ".HiddenRobot",
        parentDirectory: root,
        template: LearningProjectTemplate.groundRobotPointNavigation
    )
    await model.waitForProjectCreation()

    let projectURL = root
        .appendingPathComponent("HiddenRobot", isDirectory: true)
        .appendingPathExtension("kuyu")
    let hiddenProjectURL = root
        .appendingPathComponent(".HiddenRobot", isDirectory: true)
        .appendingPathExtension("kuyu")
    let rootContents = try FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: nil
    )
    let hiddenCreationPackages = rootContents.filter {
        $0.lastPathComponent.hasPrefix(".") && $0.lastPathComponent.contains("-creating-")
    }

    #expect(model.currentProject?.package.rootURL == projectURL)
    #expect(FileManager.default.fileExists(atPath: projectURL.path))
    #expect(!FileManager.default.fileExists(atPath: hiddenProjectURL.path))
    #expect(hiddenCreationPackages.isEmpty)
    #expect(model.projectCreationError == nil)
}

@Test(.timeLimit(.minutes(1))) func appViewModelProjectCreationStagingURLIsNotHidden() throws {
    let id = try #require(UUID(uuidString: "1298D3DD-9A87-40D8-B0D1-E419211CC5B6"))
    let stagingURL = AppViewModel.makeProjectCreationStagingURL(
        projectName: "Drone Autonomy Starter",
        id: id
    )

    #expect(stagingURL.lastPathComponent == "Drone Autonomy Starter-creating-1298D3DD-9A87-40D8-B0D1-E419211CC5B6.kuyu")
    #expect(!stagingURL.lastPathComponent.hasPrefix("."))
    #expect(stagingURL.deletingLastPathComponent().lastPathComponent == "BoundedProjectCreation")
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
        template: .droneAutonomyStarter,
        sourceBundleURL: appSourceBundleReferencePath
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
        template: .droneAutonomyStarter,
        sourceBundleURL: appSourceBundleReferencePath
    )
    let model = AppViewModel(logStore: UILogStore(buffer: UILogBuffer()))

    model.simulationViewModel.configureForProjectPackage(package)

    #expect(model.simulationViewModel.learningCampaignSuites == "6")
    #expect(model.simulationViewModel.learningCampaignSeedCount == 2)
    #expect(model.simulationViewModel.learningCampaignPopulation == 100)
    #expect(model.simulationViewModel.learningCampaignGenerations >= 1_000)
}

@MainActor
@Test(.timeLimit(.minutes(2))) func appViewModelCreatesRunnableDroneStarterThroughInjectedAssetPreparer() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-project-runnable-drone-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer {
        removeTemporaryDirectory(root)
    }

    let preparer = RecordingRunnableProjectAssetPreparer()
    let model = AppViewModel(
        logStore: UILogStore(buffer: UILogBuffer()),
        runnableProjectAssetPreparer: preparer,
        starterSourceCheckpointValidator: AcceptingStarterSourceCheckpointValidator()
    )
    model.createProject(
        name: "Drone Autonomy Starter",
        parentDirectory: root,
        template: .droneAutonomyStarter
    )
    await model.waitForProjectCreation()

    let projectURL = root
        .appendingPathComponent("Drone Autonomy Starter", isDirectory: true)
        .appendingPathExtension("kuyu")
    let sourceBundleURL = projectURL
        .appendingPathComponent("model-bundles", isDirectory: true)
        .appendingPathComponent("source.manasbundle", isDirectory: true)

    #expect(model.projectCreationError == nil)
    #expect(model.currentProject?.package.rootURL == projectURL)
    #expect(model.currentProject?.isRunnable == true)
    #expect(model.currentProject?.package.selectedTemplate.templateID == LearningProjectTemplate.droneAutonomyStarter.templateID)
    #expect(model.simulationViewModel.isLearningStarterProjectReady)
    #expect(model.simulationViewModel.learningCampaignSourceCheckpointPath == sourceBundleURL.path)
    #expect(model.simulationViewModel.learningCampaignSuites == "6")
    #expect(model.simulationViewModel.learningCampaignSeedCount == 2)
    #expect(model.simulationViewModel.learningCampaignPopulation == 100)
    #expect(model.simulationViewModel.learningCampaignGenerations >= 1_000)

    #expect(FileManager.default.fileExists(atPath: projectURL.appendingPathComponent("project.json").path))
    #expect(FileManager.default.fileExists(atPath: projectURL.appendingPathComponent("templates/selected-template.json").path))
    #expect(FileManager.default.fileExists(atPath: projectURL.appendingPathComponent("experiments/default/experiment.json").path))
    #expect(FileManager.default.fileExists(atPath: projectURL.appendingPathComponent("environments/default/environment.json").path))
    #expect(FileManager.default.fileExists(atPath: projectURL.appendingPathComponent("model-bundles/source.bundle-ref.json").path))
    #expect(FileManager.default.fileExists(atPath: sourceBundleURL.appendingPathComponent("manas-bundle.json").path))
    #expect(FileManager.default.fileExists(atPath: sourceBundleURL.appendingPathComponent("model.json").path))
    #expect(FileManager.default.fileExists(atPath: sourceBundleURL.appendingPathComponent("core.safetensors").path))

    let request = try #require(preparer.requests.first)
    #expect(preparer.requests.count == 1)
    #expect(request.checkpointURL.lastPathComponent == "source.manasbundle")
    #expect(request.displayName == "Drone Autonomy Starter")
    #expect(request.policyContract == LearningProjectTemplate.droneAutonomyStarter.policy)
    #expect(request.actionContract == LearningProjectTemplate.droneAutonomyStarter.action)
    #expect(request.observationChannelCountOverride == LearningProjectTemplate.droneAutonomyStarter.observation.channelCount)
}

@MainActor
@Test(.timeLimit(.minutes(2))) func allRunnableTemplatesDelegateSourceBundlePreparation() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-project-runnable-templates-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer {
        removeTemporaryDirectory(root)
    }

    let runnableTemplates = LearningProjectTemplateCatalog.defaultTemplates.filter(\.isRunnableStarter)
    #expect(!runnableTemplates.isEmpty)

    for template in runnableTemplates {
        let preparer = RecordingRunnableProjectAssetPreparer()
        let model = AppViewModel(
            logStore: UILogStore(buffer: UILogBuffer()),
            runnableProjectAssetPreparer: preparer,
            starterSourceCheckpointValidator: AcceptingStarterSourceCheckpointValidator()
        )
        model.createProject(
            name: template.displayName,
            parentDirectory: root,
            template: template
        )
        await model.waitForProjectCreation()

        let projectURL = root
            .appendingPathComponent(template.displayName, isDirectory: true)
            .appendingPathExtension("kuyu")
        let sourceBundleURL = projectURL
            .appendingPathComponent("model-bundles", isDirectory: true)
            .appendingPathComponent("source.manasbundle", isDirectory: true)

        #expect(model.projectCreationError == nil)
        #expect(model.currentProject?.package.selectedTemplate.templateID == template.templateID)
        #expect(model.simulationViewModel.isLearningStarterProjectReady)
        #expect(FileManager.default.fileExists(atPath: sourceBundleURL.appendingPathComponent("manas-bundle.json").path))
        #expect(FileManager.default.fileExists(atPath: sourceBundleURL.appendingPathComponent("model.json").path))
        #expect(FileManager.default.fileExists(atPath: sourceBundleURL.appendingPathComponent("core.safetensors").path))

        let request = try #require(preparer.requests.first)
        #expect(preparer.requests.count == 1)
        #expect(request.checkpointURL.lastPathComponent == "source.manasbundle")
        #expect(request.displayName == template.displayName)
        #expect(request.policyContract == template.policy)
        #expect(request.actionContract == template.action)
        #expect(request.observationChannelCountOverride == template.observation.channelCount)
    }
}

@MainActor
@Test(
    .timeLimit(.minutes(2)),
    .enabled(
        if: mlxProjectFlowEndToEndEnabled,
        "Set KUYU_MLX_RUN_PROJECT_FLOW_E2E=1 to run this real MLX project-flow smoke."
    )
)
func droneStarterTemplateRunsSmallLearningCampaignEndToEnd() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("kuyu-project-template-e2e-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer {
        removeTemporaryDirectory(root)
    }

    let template = LearningProjectTemplate.droneAutonomyStarter
    let model = AppViewModel(logStore: UILogStore(buffer: UILogBuffer()))
    model.createProject(
        name: "Drone Autonomy Starter",
        parentDirectory: root,
        template: template
    )
    await model.waitForProjectCreation()

    let projectURL = root
        .appendingPathComponent("Drone Autonomy Starter", isDirectory: true)
        .appendingPathExtension("kuyu")
    let sourceBundleURL = projectURL
        .appendingPathComponent("model-bundles", isDirectory: true)
        .appendingPathComponent("source.manasbundle", isDirectory: true)
    let artifactRoot = projectURL
        .appendingPathComponent("runs", isDirectory: true)
        .appendingPathComponent("template-e2e", isDirectory: true)
    let stage = try #require(template.primaryRunnableTrainingStage)
    let request = TrainingRunRequest(
        runID: TrainingRunID("template-e2e"),
        projectRoot: projectURL,
        artifactRoot: artifactRoot,
        taskProfileID: stage.taskProfileID ?? template.taskProfileID ?? "lift",
        policyContract: template.policy,
        actionContract: template.action,
        sourceBundle: ModelBundleReference(
            bundleID: sourceBundleURL.lastPathComponent,
            kind: .source,
            url: sourceBundleURL
        ),
        seedCount: 1,
        populationSize: 1,
        generationLimit: 1,
        configuration: TrainingRunConfiguration(
            trainingStageID: stage.stageID,
            trainingStageDisplayName: stage.displayName,
            trainingStageKind: stage.kind,
            searchScenarioSelection: TrainingScenarioSelection(
                suiteIDs: [6],
                episodesPerSuite: 1,
                tier: .tier1
            ),
            resources: TrainingResourcePlan(
                workerCount: 1,
                candidateEvaluationConcurrency: 1,
                resourceSampleSeconds: 0,
                worldExecutionRequirement: .acceleratorSharedWorld
            ),
            evolution: TrainingEvolutionSettings(
                eliteCount: 1,
                mutation: TrainingMutationSchedule(
                    rate: 0.14,
                    noiseScale: 0.025,
                    adaptiveEnabled: false
                ),
                minimumIncumbentImprovement: 0
            ),
            convergence: TrainingConvergenceSettings(enabled: false),
            qualityGate: TrainingQualityGateSettings(enabled: true),
            reinforcement: TrainingReinforcementSettings(warmupEnabled: false),
            artifacts: TrainingArtifactPolicy(
                retention: .compact,
                requiresInitialParentPass: false
            ),
            autonomyDomain: template.domain
        )
    )

    let handle = try await ManasMLXTrainingRunExecutor().start(request)
    let summary = try await handle.wait()

    #expect(summary.artifactRoot == artifactRoot)
    #expect(summary.generationCount == 1)
    #expect(summary.candidateCount == 1)
    #expect(FileManager.default.fileExists(atPath: artifactRoot.appendingPathComponent("learning-campaign-plan.json").path))
    #expect(FileManager.default.fileExists(atPath: artifactRoot.appendingPathComponent("learning-campaign-summary.json").path))
    #expect(FileManager.default.fileExists(atPath: artifactRoot.appendingPathComponent("learning-campaign-validation.json").path))
    #expect(FileManager.default.fileExists(atPath: artifactRoot.appendingPathComponent("seeds/seed-1/evolution/fitness.jsonl").path))
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
        template: .droneAutonomyStarter,
        sourceBundleURL: appSourceBundleReferencePath
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
    // The continuation resolver only harvests candidates from an evolution
    // directory whose manifest reports a terminal state, so the fixture must
    // carry the manifest a real run would have written alongside the records.
    try writeJSON(
        EvolutionRunManifest(
            runID: "resume-run",
            taskID: "lift",
            configHash: "resume-config",
            policyID: "manasMLX",
            populationSize: 4,
            generationCount: 13,
            eliteCount: 1,
            workerCount: 1,
            startedAt: Date(timeIntervalSince1970: 0),
            completedAt: Date(timeIntervalSince1970: 1),
            terminalState: .completed
        ),
        to: evolution.appendingPathComponent("evolution-manifest.json")
    )
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

    let continuation = try LearningCampaignContinuationResolver().resolve(from: run)
    #expect(continuation.checkpointURL.standardizedFileURL == candidateCheckpoint.standardizedFileURL)

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

private let appSourceBundleReferencePath = "model-bundles/source.manasbundle"

private let mlxProjectFlowEndToEndEnabled =
    ProcessInfo.processInfo.environment["KUYU_MLX_RUN_PROJECT_FLOW_E2E"] == "1"

@MainActor
private final class RecordingRunnableProjectAssetPreparer: RunnableProjectAssetPreparing {
    private(set) var requests: [RunnableProjectAssetPreparationRequest] = []

    func prepareSourceCheckpoint(request: RunnableProjectAssetPreparationRequest) async throws {
        requests.append(request)
        try writeCompleteCheckpointSkeleton(at: request.checkpointURL)
    }
}

@MainActor
private struct AcceptingStarterSourceCheckpointValidator: StarterSourceCheckpointValidating {
    func validate(request: StarterSourceCheckpointValidationRequest) throws {}
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
        "embodimentHash" : "embodiment",
        "driveSemanticsID" : "drive",
        "observationSchemaID" : "observation"
      },
      "schemaVersion" : 1
    }
    """
}

/// Encodes fixtures the way `EvolutionRunArtifactWriter` encodes real artifacts.
///
/// Readers of these directories decode with `.iso8601` dates and string-encoded
/// non-conforming floats, so a fixture written with a default encoder is a shape
/// production never produces.
private func makeProjectFlowFixtureEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.nonConformingFloatEncodingStrategy = .convertToString(
        positiveInfinity: "Infinity",
        negativeInfinity: "-Infinity",
        nan: "NaN"
    )
    return encoder
}

private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = makeProjectFlowFixtureEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    try data.write(to: url, options: .atomic)
}

private func writeJSONLines<T: Encodable>(_ values: [T], to url: URL) throws {
    let encoder = makeProjectFlowFixtureEncoder()
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
        searchSuites: ["6"],
        searchEpisodes: 1,
        acceptanceSuites: ["6"],
        acceptanceEpisodes: 1,
        workers: 1,
        population: 100,
        generations: 1_000,
        eliteCount: 10,
        candidateEvaluationConcurrency: 100,
        cutPeriodSteps: 2,
        seeds: ["1"],
        sourceCheckpoint: nil,
        robotManifest: nil,
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
