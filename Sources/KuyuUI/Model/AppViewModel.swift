import Foundation
import KuyuScenarios
import KuyuTraining
import Observation

/// Root view model that manages application mode and delegates to mode-specific view models
@Observable
@MainActor
public final class AppViewModel {
    /// Application operating mode
    public enum Mode: String, CaseIterable, Sendable {
        case simulation
        case training

        public var displayName: String {
            switch self {
            case .simulation: return "Simulation"
            case .training: return "Training"
            }
        }
    }

    // MARK: - Mode Management

    /// Current application mode
    public var currentMode: Mode = .simulation
    public var selectedWorkspace: BoundedWorkspace = .dashboard
    public var selectedTrainingPhase: BoundedTrainingPhase = .strategy
    public var selectedProjectName: String = "Bounded"
    public var availableProjectNames: [String] {
        if let currentProject {
            return [currentProject.package.manifest.name]
        }
        return []
    }
    public var currentProject: KuyuProjectSession?
    public var currentModelBundleURL: URL?
    public var recentProjectURLs: [URL] = []
    public var projectCreationError: String?
    public var isCreatingProject = false
    public var projectTemplates: [LearningProjectTemplate] {
        LearningProjectTemplateCatalog.defaultTemplates
    }
    public var selectedEnvironmentName: String = "QuadLift-v1" {
        didSet { applySelectedEnvironment() }
    }

    // MARK: - Mode-Specific ViewModels

    /// Simulation mode state
    public let simulationViewModel: SimulationViewModel

    // MARK: - Shared Resources

    /// Shared log store across all modes
    public let logStore: UILogStore

    // MARK: - Initialization

    public init(logStore: UILogStore, prepareStarterProjectOnInit: Bool = false) {
        self.logStore = logStore
        self.simulationViewModel = SimulationViewModel(
            logStore: logStore,
            prepareStarterProjectOnInit: prepareStarterProjectOnInit
        )
        applySelectedEnvironment()
    }

    public func openURL(_ url: URL) {
        switch url.pathExtension.lowercased() {
        case "kuyu":
            openProject(at: url)
        case "manasbundle":
            openModelBundle(at: url)
        default:
            projectCreationError = "Unsupported file type: \(url.lastPathComponent)"
        }
    }

    public func openProject(at url: URL) {
        do {
            let package = try KuyuProjectPackageLoader().load(from: url)
            try validateProjectSession(package)
            currentProject = KuyuProjectSession(
                package: package,
                openedAt: Date(),
                isRunnable: package.selectedTemplate.taskProfileID != nil
            )
            selectedProjectName = package.manifest.name
            selectedWorkspace = .dashboard
            simulationViewModel.configureForProjectPackage(package)
            rememberProjectURL(url)
            projectCreationError = nil
        } catch {
            projectCreationError = "\(error)"
        }
    }

    public func openModelBundle(at url: URL) {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            projectCreationError = KuyuProjectSessionError.missingSourceBundle(path: url.path).description
            return
        }
        currentModelBundleURL = url
        selectedWorkspace = .system
        projectCreationError = nil
    }

    public func createProject(
        name: String,
        parentDirectory: URL,
        template: LearningProjectTemplate
    ) {
        isCreatingProject = true
        projectCreationError = nil
        do {
            let projectName = sanitizedProjectName(name)
            let targetURL = parentDirectory
                .appendingPathComponent(projectName, isDirectory: true)
                .appendingPathExtension("kuyu")
            guard !FileManager.default.fileExists(atPath: targetURL.path) else {
                throw KuyuProjectPackageError.packageAlreadyExists(path: targetURL.path)
            }
            let temporaryURL = parentDirectory
                .appendingPathComponent(".\(projectName)-creating-\(UUID().uuidString)", isDirectory: true)
                .appendingPathExtension("kuyu")
            do {
                let package = try KuyuProjectFactory().makeRunnableStarterProject(
                    rootURL: temporaryURL,
                    name: projectName,
                    template: template
                )
                try KuyuProjectPackageWriter().write(package)
                if template.taskProfileID != nil {
                    try simulationViewModel.prepareRunnableProjectAssets(for: package)
                }
                try FileManager.default.moveItem(at: temporaryURL, to: targetURL)
            } catch {
                if FileManager.default.fileExists(atPath: temporaryURL.path) {
                    do {
                        try FileManager.default.removeItem(at: temporaryURL)
                    } catch {
                        projectCreationError = "Cleanup failed: \(error)"
                    }
                }
                throw error
            }
            openProject(at: targetURL)
        } catch {
            projectCreationError = "\(error)"
        }
        isCreatingProject = false
    }

    private func applySelectedEnvironment() {
        switch selectedEnvironmentName {
        case "SinglePropLift-v1":
            simulationViewModel.taskMode = .singleLift
        case "QuadLift-v1":
            simulationViewModel.taskMode = .lift
        default:
            simulationViewModel.taskMode = .attitude
        }
    }

    private func rememberProjectURL(_ url: URL) {
        recentProjectURLs.removeAll { $0 == url }
        recentProjectURLs.insert(url, at: 0)
        if recentProjectURLs.count > 8 {
            recentProjectURLs = Array(recentProjectURLs.prefix(8))
        }
    }

    private func sanitizedProjectName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmed.isEmpty ? "Untitled" : trimmed
        let invalid = CharacterSet(charactersIn: "/:")
        return fallback
            .components(separatedBy: invalid)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }

    private func validateProjectSession(_ package: KuyuProjectPackage) throws {
        guard package.manifest.validationPolicy.requiresModelBundleCompatibility else {
            return
        }
        let bundleURL = try resolvedProjectURL(
            package.sourceBundleReference.url,
            relativeTo: package.rootURL
        )
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: bundleURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw KuyuProjectSessionError.missingSourceBundle(path: bundleURL.path)
        }
    }

    private func resolvedProjectURL(_ reference: String, relativeTo rootURL: URL) throws -> URL {
        if reference.hasPrefix("/") {
            return URL(fileURLWithPath: reference)
        }
        if let url = URL(string: reference), let scheme = url.scheme {
            guard scheme == "file" else {
                throw KuyuProjectSessionError.unsupportedSourceBundleURL(reference)
            }
            return url
        }
        return rootURL.appendingPathComponent(reference, isDirectory: true)
    }
}
