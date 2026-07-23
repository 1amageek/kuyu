import ArgumentParser
import Foundation
import KuyuCore
import KuyuMLXReferenceQuadrotor
import KuyuPhysics

extension RunFoundationAcceptance {
    func validatePositiveFoundationAcceptanceInputs() throws {
        guard seedCount > 0 else { throw ValidationError("--seed-count must be greater than 0.") }
        guard population > 0 else { throw ValidationError("--population must be greater than 0.") }
        guard generations > 0 else { throw ValidationError("--generations must be greater than 0.") }
        guard eliteCount > 0, eliteCount <= population else {
            throw ValidationError("--elite-count must be between 1 and --population.")
        }
        guard workers > 0 else { throw ValidationError("--workers must be greater than 0.") }
        guard candidateEvaluationConcurrency > 0,
              candidateEvaluationConcurrency <= population else {
            throw ValidationError("--candidate-evaluation-concurrency must be between 1 and --population.")
        }
        guard episodes > 0 else { throw ValidationError("--episodes must be greater than 0.") }
        guard reinforcementWarmupDuration.isFinite, reinforcementWarmupDuration > 0 else {
            throw ValidationError("--reinforcement-warmup-duration must be finite and greater than 0.")
        }
        guard reinforcementWarmupIterations > 0 else {
            throw ValidationError("--reinforcement-warmup-iterations must be greater than 0.")
        }
        guard reinforcementWarmupLearningRate.isFinite, reinforcementWarmupLearningRate > 0 else {
            throw ValidationError("--reinforcement-warmup-learning-rate must be finite and greater than 0.")
        }
        if let reinforcementWarmupMaxBatches, reinforcementWarmupMaxBatches <= 0 {
            throw ValidationError("--reinforcement-warmup-max-batches must be greater than 0 when specified.")
        }
        guard m2EpisodesPerSuite > 0 else {
            throw ValidationError("--m2-episodes-per-suite must be greater than 0.")
        }
        if let m2MaxStepsPerEpisode, m2MaxStepsPerEpisode <= 0 {
            throw ValidationError("--m2-max-steps-per-episode must be greater than 0 when specified.")
        }
        guard (0...8).contains(defaultStressSuite) else {
            throw ValidationError("--default-stress-suite must be between 0 and 8.")
        }
        if let defaultStressEpisodes, defaultStressEpisodes <= 0 {
            throw ValidationError("--default-stress-episodes must be greater than 0 when specified.")
        }
        let completedCampaignPath = completedCampaignArtifactRootPath?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if writeDefaultPhysicsCorpusAcceptance,
           completedCampaignPath == nil,
           model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ValidationError("--model is required when --write-default-physics-corpus-acceptance is set.")
        }
        if completedCampaignPath?.isEmpty == true {
            throw ValidationError(
                "--completed-campaign-artifact-root must not be empty when specified."
            )
        }
        if completedCampaignPath != nil,
           (!sourceCheckpointPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
               || writeDefaultSourceCheckpoint) {
            throw ValidationError(
                "--completed-campaign-artifact-root is mutually exclusive with source checkpoint options."
            )
        }
        if completedCampaignPath == nil,
           sourceCheckpointPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !writeDefaultSourceCheckpoint {
            throw ValidationError("--source-checkpoint is required unless --write-default-source-checkpoint is set.")
        }
        guard defaultSourceHiddenSize > 0 else {
            throw ValidationError("--default-source-hidden-size must be greater than 0.")
        }
        guard resourceSampleSeconds.isFinite, resourceSampleSeconds >= 0 else {
            throw ValidationError("--resource-sample-seconds must be finite and non-negative.")
        }
    }

    func parseFoundationAcceptanceSeeds(_ raw: String) throws -> [String] {
        let values = raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !values.isEmpty else {
            throw ValidationError("--seeds must include at least one seed.")
        }
        var seenSeeds = Set<String>()
        var parsedSeeds: [String] = []
        for value in values {
            guard let seed = UInt64(value) else {
                throw ValidationError("--seeds contains an invalid unsigned integer seed: \(value)")
            }
            let canonicalValue = String(seed)
            guard seenSeeds.insert(canonicalValue).inserted else {
                throw ValidationError("--seeds contains a duplicate seed: \(canonicalValue)")
            }
            parsedSeeds.append(canonicalValue)
        }
        return parsedSeeds
    }

    func parseFoundationAcceptanceSuites(_ raw: String) throws -> [Int] {
        let values = raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !values.isEmpty else {
            throw ValidationError("--suites must include at least one suite.")
        }
        var seenSuites = Set<Int>()
        var suites: [Int] = []
        for value in values {
            guard let suite = Int(value), (0...8).contains(suite) else {
                throw ValidationError("--suites contains an unsupported suite: \(value)")
            }
            guard seenSuites.insert(suite).inserted else {
                throw ValidationError("--suites contains a duplicate suite: \(suite)")
            }
            suites.append(suite)
        }
        return suites
    }

    func parseFoundationAcceptanceM2Suites(_ raw: String) throws -> [Int] {
        let values = raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !values.isEmpty else {
            throw ValidationError("--m2-suites must include at least one suite.")
        }
        var seenSuites = Set<Int>()
        var suites: [Int] = []
        for value in values {
            guard let suite = Int(value), (6...8).contains(suite) else {
                throw ValidationError("--m2-suites contains an unsupported suite: \(value)")
            }
            guard seenSuites.insert(suite).inserted else {
                throw ValidationError("--m2-suites contains a duplicate suite: \(suite)")
            }
            suites.append(suite)
        }
        return suites
    }

    func parseFoundationAcceptanceStressSuiteManifestURLs(
        _ raw: String?,
        artifactRoot: URL
    ) throws -> [URL] {
        try parseFoundationAcceptanceRootContainedURLs(
            raw,
            optionName: "--stress-suite-manifests",
            artifactRoot: artifactRoot
        )
    }

    func parseFoundationAcceptancePhysicsCorpusAcceptanceURLs(
        _ raw: String?,
        artifactRoot: URL
    ) throws -> [URL] {
        try parseFoundationAcceptanceRootContainedURLs(
            raw,
            optionName: "--physics-corpus-acceptance-artifacts",
            artifactRoot: artifactRoot
        )
    }

    func parseFoundationAcceptanceRootContainedURLs(
        _ raw: String?,
        optionName: String,
        artifactRoot: URL
    ) throws -> [URL] {
        guard let raw else {
            return []
        }
        let values = raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !values.isEmpty else {
            throw ValidationError("\(optionName) must include at least one path when specified.")
        }
        let rootPath = artifactRoot.standardizedFileURL.path
        var seenPaths = Set<String>()
        var urls: [URL] = []
        for value in values {
            let url = URL(fileURLWithPath: value).standardizedFileURL
            let path = url.path
            guard path.hasPrefix(rootPath + "/") else {
                throw ValidationError("\(optionName) must be under --artifact-root: \(path)")
            }
            guard seenPaths.insert(path).inserted else {
                throw ValidationError("\(optionName) contains a duplicate path: \(path)")
            }
            urls.append(url)
        }
        return urls
    }

    func defaultFoundationStressSuiteManifestURL(artifactRoot: URL) -> URL {
        artifactRoot
            .appendingPathComponent("stress", isDirectory: true)
            .appendingPathComponent("reference-quadrotor-foundation-stress.json", isDirectory: false)
    }

    func defaultFoundationPhysicsCorpusAcceptanceURL(artifactRoot: URL) -> URL {
        artifactRoot
            .appendingPathComponent("physics", isDirectory: true)
            .appendingPathComponent(DescriptorCorpusAcceptanceArtifactStore.fileName, isDirectory: false)
    }

    func foundationAcceptanceSourceCheckpointURL(artifactRoot: URL) throws -> URL {
        let trimmedSourcePath = sourceCheckpointPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let outputURL = trimmedSourcePath.isEmpty
            ? defaultFoundationSourceCheckpointURL(artifactRoot: artifactRoot)
            : URL(fileURLWithPath: trimmedSourcePath, isDirectory: true).standardizedFileURL
        guard writeDefaultSourceCheckpoint else {
            return outputURL
        }
        return try writeDefaultFoundationSourceCheckpoint(
            outputURL: outputURL,
            artifactRoot: artifactRoot
        )
    }

    func defaultFoundationSourceCheckpointURL(artifactRoot: URL) -> URL {
        artifactRoot
            .appendingPathComponent("source", isDirectory: true)
            .appendingPathComponent("reference-quadrotor-foundation-source.manasbundle", isDirectory: true)
            .standardizedFileURL
    }

    @discardableResult
    func writeDefaultFoundationSourceCheckpoint(
        outputURL: URL,
        artifactRoot: URL
    ) throws -> URL {
        let result = try ReferenceQuadrotorFoundationSourceCheckpointService().write(
            ReferenceQuadrotorFoundationSourceCheckpointRequest(
                outputURL: outputURL,
                name: defaultSourceCheckpointName,
                robotManifestPath: model,
                hiddenSize: defaultSourceHiddenSize,
                initializationSeed: ReferenceQuadrotorStarterCheckpointContractService()
                    .defaultContract(for: .attitude)
                    .initializationSeed
            ),
            artifactRoot: artifactRoot
        )
        print("[foundation-acceptance] sourceCheckpointWritten=\(result.checkpointURL.path)")
        print("[foundation-acceptance] sourceCheckpointObservationSchema=\(result.manifest.observationSchemaID)")
        print("[foundation-acceptance] sourceCheckpointHiddenSize=\(result.manifest.config.hiddenSize)")
        return result.checkpointURL
    }

    @discardableResult
    func writeDefaultFoundationStressSuiteManifest(
        outputURL: URL,
        artifactRoot: URL,
        configuration: FoundationAcceptanceEvidenceConfiguration
    ) async throws -> URL {
        let episodeCount = defaultStressEpisodes ?? m2EpisodesPerSuite
        let writtenURL = try await ReferenceQuadrotorFoundationStressSuiteManifestService().write(
            ReferenceQuadrotorFoundationStressSuiteManifestRequest(
                suite: defaultStressSuite,
                episodeCount: episodeCount,
                outputURL: outputURL,
                tier: configuration.tier,
                cutPeriodSteps: configuration.cutPeriodSteps,
                robotManifestPath: configuration.robotManifestPath,
                coverageMode: defaultStressScenarioSuite ? .scenarioSuite : .referenceM2Benchmark,
                kp: configuration.kp,
                kd: configuration.kd,
                yawDamping: configuration.yawDamping,
                hoverScale: configuration.hoverScale
            ),
            artifactRoot: artifactRoot
        )
        print("[foundation-acceptance] stressManifest=\(writtenURL.path)")
        return writtenURL
    }

    @discardableResult
    func writeDefaultFoundationPhysicsCorpusAcceptance(
        outputURL: URL,
        artifactRoot: URL,
        configuration: FoundationAcceptanceEvidenceConfiguration
    ) async throws -> URL {
        let loadedRobot = try KuyuModelLoader().loadRobot(path: configuration.robotManifestPath)
        let publication = try await LoadedRobotDescriptorCorpusAcceptanceService().write(
            LoadedRobotDescriptorCorpusAcceptanceRequest(
                corpusID: "reference-foundation-default-physics-corpus",
                loadedRobots: [loadedRobot],
                outputDirectory: outputURL.deletingLastPathComponent(),
                artifactRoot: artifactRoot,
                requiredReadiness: .dynamicSimulation,
                durationSteps: 4,
                seedBase: 42
            )
        )
        let writtenURL = publication.artifactURL.standardizedFileURL
        let expectedURL = outputURL.standardizedFileURL
        guard writtenURL == expectedURL else {
            throw ValidationError(
                "default physics corpus writer returned unexpected path: \(writtenURL.path)"
            )
        }
        print("[foundation-acceptance] physicsCorpus=\(writtenURL.path)")
        print("[foundation-acceptance] physicsCorpusRecords=\(publication.summary.records.count) accepted=\(publication.summary.accepted)")
        return writtenURL
    }

    func appendFoundationAcceptanceStressSuiteManifestURL(
        _ url: URL,
        to urls: inout [URL]
    ) throws {
        let path = url.standardizedFileURL.path
        let existingPaths = Set(urls.map { $0.standardizedFileURL.path })
        guard !existingPaths.contains(path) else {
            throw ValidationError("--stress-suite-manifests contains a duplicate path: \(path)")
        }
        urls.append(url.standardizedFileURL)
    }

    func appendFoundationAcceptancePhysicsCorpusAcceptanceURL(
        _ url: URL,
        to urls: inout [URL]
    ) throws {
        let path = url.standardizedFileURL.path
        let existingPaths = Set(urls.map { $0.standardizedFileURL.path })
        guard !existingPaths.contains(path) else {
            throw ValidationError(
                "--physics-corpus-acceptance-artifacts contains a duplicate path: \(path)"
            )
        }
        urls.append(url.standardizedFileURL)
    }

    func parseFoundationAcceptanceProjectEvidencePackDirectory(
        _ raw: String?
    ) throws -> URL? {
        guard let raw else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ValidationError("--incumbent-project-evidence-pack must include a directory path when specified.")
        }
        return URL(fileURLWithPath: trimmed, isDirectory: true).standardizedFileURL
    }

    static func printFoundationAcceptanceEvent(
        _ event: ReferenceQuadrotorFoundationAcceptanceEvent
    ) {
        switch event {
        case .campaign(let campaignEvent):
            print("[foundation-acceptance] campaign event=\(String(describing: campaignEvent))")
        case .finalEvaluationStarted(let checkpointPath, let artifactRootPath):
            print("[foundation-acceptance] final-evaluation started checkpoint=\(checkpointPath) artifactRoot=\(artifactRootPath)")
        case .finalEvaluationCompleted(let accepted, let artifactRootPath):
            print("[foundation-acceptance] final-evaluation completed accepted=\(accepted) artifactRoot=\(artifactRootPath)")
        case .m2BenchmarkStarted(let checkpointPath, let artifactRootPath):
            print("[foundation-acceptance] m2-benchmark started checkpoint=\(checkpointPath) artifactRoot=\(artifactRootPath)")
        case .m2BenchmarkCompleted(let allPassed, let artifactRootPath):
            print("[foundation-acceptance] m2-benchmark completed allPassed=\(allPassed) artifactRoot=\(artifactRootPath)")
        case .projectEvidenceCompared(let decision, let dominantFactor):
            print("[foundation-acceptance] project-evidence compared decision=\(decision.rawValue) dominantFactor=\(dominantFactor.rawValue)")
        case .projectEvidencePackWritten(let path):
            print("[foundation-acceptance] project-evidence-pack-written path=\(path)")
        case .artifactWritten(let path):
            print("[foundation-acceptance] artifact-written path=\(path)")
        case .publicationCleanupDeferred(let path):
            print("[foundation-acceptance] publication-cleanup-deferred path=\(path)")
        }
    }
}
