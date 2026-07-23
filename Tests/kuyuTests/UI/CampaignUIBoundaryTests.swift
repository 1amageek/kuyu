import Foundation
import Testing

@Suite("Campaign UI boundary")
struct CampaignUIBoundaryTests {
    @Test func artifactStoreUsesTypedReader() throws {
        let root = packageRoot()
        let readerSource = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/KuyuUI/Services/KuyuUITrainingArtifactReader.swift",
                isDirectory: false
            ),
            encoding: .utf8
        )
        let campaignStoreSource = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/KuyuUI/Services/LearningCampaignRunStore.swift",
                isDirectory: false
            ),
            encoding: .utf8
        )

        #expect(readerSource.contains("public protocol KuyuUITrainingArtifactReading"))
        #expect(readerSource.contains("public struct KuyuUITrainingArtifactReader"))
        #expect(readerSource.contains("GeneratedTrainingArtifactCompatibilityVerifier"))
        #expect(readerSource.contains("func validatedVectorizedBatches"))
        #expect(readerSource.contains("ManasMLXVectorizedEvaluationArtifactValidator"))
        #expect(readerSource.contains("ManasMLXVectorizedGenomeVariationArtifactValidator"))
        #expect(campaignStoreSource.contains("private let artifactReader: any KuyuUITrainingArtifactReading"))
        #expect(campaignStoreSource.contains("artifactReader.validatedEvolutionArtifacts"))
        #expect(campaignStoreSource.contains("artifactReader.validatedVectorizedBatches"))
        #expect(!campaignStoreSource.contains("GeneratedTrainingArtifactCompatibilityVerifier"))
        #expect(!campaignStoreSource.contains("ManasMLXVectorizedEvaluationArtifact.self"))
        #expect(!campaignStoreSource.contains("ManasMLXVectorizedGenomeVariationArtifact.self"))
    }

    @Test func commandSystemUsesMainActorIsolation() throws {
        let source = try String(
            contentsOf: packageRoot().appendingPathComponent(
                "Sources/KuyuUI/Services/CommandSystem.swift",
                isDirectory: false
            ),
            encoding: .utf8
        )

        #expect(source.contains("@MainActor"))
        #expect(!source.contains("NSLock"))
    }

    @Test func commandSystemDelegatesTrainingLifecycleToInjectedExecutor() throws {
        let source = try String(
            contentsOf: packageRoot().appendingPathComponent(
                "Sources/KuyuUI/Services/CommandSystem.swift",
                isDirectory: false
            ),
            encoding: .utf8
        )

        #expect(source.contains("private let trainingRunExecutor: any AnyTrainingRunExecuting"))
        #expect(source.contains("trainingRunExecutor: (any AnyTrainingRunExecuting)? = nil"))
        #expect(source.contains("ManasMLXTrainingRunProcessExecutor(configuration: configuration)"))
        #expect(!source.contains("trainingRunExecutor: any AnyTrainingRunExecuting = ManasMLXTrainingRunExecutor()"))
        #expect(source.contains("try await trainingRunExecutor.start(request)"))
        #expect(source.contains("try await trainingRunExecutor.resume(request)"))
        #expect(source.contains("try trainingRunExecutor.validate(request)"))
        #expect(!source.contains("ReferenceQuadrotorTrainingBackendBundleFactory"))
        #expect(!source.contains("ManasMLXTrainingBackendFactory"))
    }

    @Test func legacyTrainingLoopBoundaryIsAbsent() throws {
        let root = packageRoot()
        let removedPaths = [
            "Sources/KuyuUI/Model/TrainingLiveStatus.swift",
            "Sources/KuyuUI/Model/TrainingTimelineEntry.swift",
            "Sources/KuyuUI/Services/TrainingBootstrapCoordinator.swift",
            "Sources/KuyuUI/Services/TrainingLoopController.swift",
            "Sources/KuyuUI/Services/TrainingLoopEventAdapter.swift",
            "Sources/KuyuUI/Services/TrainingLoopStateReducer.swift",
            "Sources/KuyuUI/Services/TrainingRunCoordinator.swift",
            "Sources/KuyuUI/Services/TrainingRunPresenter.swift",
            "Sources/KuyuUI/Services/TrainingRunStore.swift",
            "Sources/KuyuUI/Services/TrainingService.swift",
            "Sources/KuyuUI/Views/TrainingConfigurationView.swift",
        ]

        for path in removedPaths {
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path))
        }

        let commandSystemSource = try source(
            at: "Sources/KuyuUI/Services/CommandSystem.swift",
            packageRoot: root
        )
        let viewModelSource = try source(
            at: "Sources/KuyuUI/Model/SimulationViewModel.swift",
            packageRoot: root
        )
        let forbiddenCommandSymbols = [
            "case trainCore",
            "startTrainingLoop",
            "pauseTrainingLoop",
            "resumeTrainingLoop",
            "stopTrainingLoop",
            "TrainingLoopCommandExecuting",
        ]
        let forbiddenViewModelSymbols = [
            "func runTraining(",
            "func trainCoreModel(",
            "func startTrainingLoop(",
            "isLoopRunning",
            "isLoopPaused",
            "TrainingLoopStateReducer",
        ]

        for symbol in forbiddenCommandSymbols {
            #expect(!commandSystemSource.contains(symbol))
        }
        for symbol in forbiddenViewModelSymbols {
            #expect(!viewModelSource.contains(symbol))
        }
    }

    @Test func campaignUIExposesOnlyExecutableControls() throws {
        let root = packageRoot()
        let runWorkspaceSource = try source(
            at: "Sources/KuyuUI/Views/RunWorkspaceView.swift",
            packageRoot: root
        )
        let launchValidationSource = try source(
            at: "Sources/KuyuUI/Views/LaunchValidationView.swift",
            packageRoot: root
        )
        let reinforcementSource = try source(
            at: "Sources/KuyuUI/Views/ReinforcementLearningConfigView.swift",
            packageRoot: root
        )
        let viewModelSource = try source(
            at: "Sources/KuyuUI/Model/SimulationViewModel.swift",
            packageRoot: root
        )
        let resultsSource = try source(
            at: "Sources/KuyuUI/Views/ResultsWorkspaceView.swift",
            packageRoot: root
        )
        let startLearningCampaignStart = try #require(
            viewModelSource.range(of: "func startLearningCampaign()")?.lowerBound
        )
        let startLearningCampaignEnd = try #require(
            viewModelSource.range(
                of: "func continueLearningCampaignFromLastCheckpoint()",
                range: startLearningCampaignStart..<viewModelSource.endIndex
            )?.lowerBound
        )
        let startLearningCampaignSource = viewModelSource[
            startLearningCampaignStart..<startLearningCampaignEnd
        ]

        #expect(!runWorkspaceSource.contains("runBaseline"))
        #expect(!runWorkspaceSource.contains("baselineSection"))
        #expect(!runWorkspaceSource.contains("Template Configured"))
        #expect(!runWorkspaceSource.contains("Environment Configured"))
        #expect(!runWorkspaceSource.contains("Strategy Configured"))
        #expect(!launchValidationSource.contains("Queue Run"))
        #expect(!viewModelSource.contains("queueLearningCampaignRun"))
        #expect(!reinforcementSource.contains("trainingEpochs"))
        #expect(!reinforcementSource.contains("trainingSequenceLength"))
        #expect(!reinforcementSource.contains("trainingLearningRate"))
        #expect(!reinforcementSource.contains("trainingInputDirectory"))
        #expect(reinforcementSource.contains("learningCampaignEpisodes"))
        #expect(reinforcementSource.contains("trainingUseQualityGating"))
        #expect(reinforcementSource.contains("learningCampaignRequiresInitialParentPass"))
        #expect(startLearningCampaignSource.contains("if isRunning"))
        #expect(startLearningCampaignSource.contains("message: \"Simulation run already active\""))
        #expect(startLearningCampaignSource.contains("action: \"startLearningCampaign\""))
        #expect(startLearningCampaignSource.contains("return"))
        #expect(resultsSource.contains("resultsModel.learningCampaignState"))
        #expect(resultsSource.contains("CampaignSessionResultsView"))
        #expect(resultsSource.contains("state.failureReasons"))
        #expect(resultsSource.contains("state.finalCheckpoint"))
    }

    private func source(at path: String, packageRoot: URL) throws -> String {
        try String(
            contentsOf: packageRoot.appendingPathComponent(path, isDirectory: false),
            encoding: .utf8
        )
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
