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
    private var projectCreationTask: Task<Void, Never>?
    private var projectCreationSessionID: UUID?
    private var inactiveProjectCleanupError: String?
    private let recentProjectsDefaults: UserDefaults
    private var currentProjectAccessURL: URL?
    private var currentProjectAccessIsScoped = false
    private var currentModelBundleAccessURL: URL?
    private var currentModelBundleAccessIsScoped = false
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

    public init(
        logStore: UILogStore,
        prepareStarterProjectOnInit: Bool = false,
        recentProjectsDefaults: UserDefaults = .standard
    ) {
        self.logStore = logStore
        self.recentProjectsDefaults = recentProjectsDefaults
        self.simulationViewModel = SimulationViewModel(
            logStore: logStore,
            prepareStarterProjectOnInit: prepareStarterProjectOnInit
        )
        self.recentProjectURLs = Self.loadRecentProjectURLs(defaults: recentProjectsDefaults)
        applySelectedEnvironment()
    }

    public func openURL(_ url: URL) {
        switch url.pathExtension.lowercased() {
        case "kuyu":
            openProject(at: url)
        case "manasbundle":
            openModelBundle(at: url)
        default:
            projectCreationError = AppViewModelErrorFormatter.message(
                for: AppViewModelError.unsupportedFileType(url.lastPathComponent)
            )
        }
    }

    public func openProject(at url: URL) {
        do {
            let resolvedURL = try resolveProjectURL(url)
            beginProjectAccess(resolvedURL)
            do {
                let package = try KuyuProjectPackageLoader().load(from: resolvedURL)
                try validateProjectSession(package)
                currentProject = KuyuProjectSession(
                    package: package,
                    openedAt: Date(),
                    isRunnable: package.selectedTemplate.isRunnableStarter
                )
                selectedProjectName = package.manifest.name
                selectedWorkspace = .dashboard
                simulationViewModel.configureForProjectPackage(package)
                rememberProjectURL(resolvedURL)
                projectCreationError = nil
            } catch {
                endProjectAccess()
                throw error
            }
        } catch {
            projectCreationError = AppViewModelErrorFormatter.message(for: error)
        }
    }

    public func openModelBundle(at url: URL) {
        let accessStarted = url.startAccessingSecurityScopedResource()
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            if accessStarted {
                url.stopAccessingSecurityScopedResource()
            }
            projectCreationError = AppViewModelErrorFormatter.message(
                for: KuyuProjectSessionError.missingSourceBundle(path: url.path)
            )
            return
        }
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            if accessStarted {
                url.stopAccessingSecurityScopedResource()
            }
            projectCreationError = AppViewModelErrorFormatter.message(
                for: AppViewModelError.unreadableModelBundle(url.path)
            )
            return
        }
        endModelBundleAccess()
        currentModelBundleAccessURL = url
        currentModelBundleAccessIsScoped = accessStarted
        currentModelBundleURL = url
        selectedWorkspace = .system
        projectCreationError = nil
    }

    public func createProject(
        name: String,
        parentDirectory: URL,
        template: LearningProjectTemplate
    ) {
        projectCreationTask?.cancel()
        let sessionID = UUID()
        projectCreationSessionID = sessionID
        projectCreationTask = Task { [weak self] in
            await self?.createProjectOperation(
                sessionID: sessionID,
                name: name,
                parentDirectory: parentDirectory,
                template: template
            )
        }
    }

    public func waitForProjectCreation() async {
        await projectCreationTask?.value
    }

    private func createProjectOperation(
        sessionID: UUID,
        name: String,
        parentDirectory: URL,
        template: LearningProjectTemplate
    ) async {
        isCreatingProject = true
        projectCreationError = nil
        let projectName = sanitizedProjectName(name)
        let targetURL = parentDirectory
            .appendingPathComponent(projectName, isDirectory: true)
            .appendingPathExtension("kuyu")
        let temporaryURL = parentDirectory
            .appendingPathComponent(".\(projectName)-creating-\(UUID().uuidString)", isDirectory: true)
            .appendingPathExtension("kuyu")
        let parentAccessStarted = parentDirectory.startAccessingSecurityScopedResource()
        defer {
            if parentAccessStarted {
                parentDirectory.stopAccessingSecurityScopedResource()
            }
            finishProjectCreationSessionIfActive(sessionID)
        }

        do {
            let package = try await Task.detached {
                try Self.makeAndWriteProjectPackage(
                    projectName: projectName,
                    targetURL: targetURL,
                    temporaryURL: temporaryURL,
                    template: template
                )
            }.value
            try Task.checkCancellation()

            if template.isRunnableStarter {
                try simulationViewModel.prepareRunnableProjectAssets(for: package)
            }
            try Task.checkCancellation()

            try await Task.detached {
                try FileManager.default.moveItem(at: temporaryURL, to: targetURL)
            }.value
            try Task.checkCancellation()

            guard projectCreationSessionIsActive(sessionID) else {
                return
            }
            openProject(at: targetURL)
        } catch is CancellationError {
            guard projectCreationSessionIsActive(sessionID) else {
                cleanupTemporaryProjectWithoutPublishing(at: temporaryURL)
                return
            }
            cleanupTemporaryProject(at: temporaryURL, primaryError: AppViewModelError.projectCreationCancelled)
        } catch {
            guard projectCreationSessionIsActive(sessionID) else {
                cleanupTemporaryProjectWithoutPublishing(at: temporaryURL)
                return
            }
            cleanupTemporaryProject(at: temporaryURL, primaryError: error)
        }
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
        let standardizedURL = url.standardizedFileURL
        recentProjectURLs.removeAll { $0.standardizedFileURL == standardizedURL }
        recentProjectURLs.insert(standardizedURL, at: 0)
        if recentProjectURLs.count > 8 {
            recentProjectURLs = Array(recentProjectURLs.prefix(8))
        }
        persistRecentProjectURLs()
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

    private static func loadRecentProjectURLs(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) -> [URL] {
        var seen = Set<String>()
        var urls: [URL] = []
        for record in recentProjectRecords(defaults: defaults) {
            let url = record.resolvedURL().standardizedFileURL
            guard url.pathExtension.lowercased() == "kuyu",
                  fileManager.fileExists(atPath: url.path),
                  seen.insert(url.path).inserted else {
                continue
            }
            urls.append(url)
            if urls.count == 8 {
                break
            }
        }
        return urls
    }

    private func persistRecentProjectURLs() {
        var records: [RecentProjectAccessRecord] = []
        for url in recentProjectURLs {
            guard let bookmarkData = makeSecurityScopedBookmarkData(for: url) else {
                continue
            }
            records.append(RecentProjectAccessRecord(path: url.path, bookmarkData: bookmarkData))
        }
        do {
            let data = try PropertyListEncoder().encode(records)
            recentProjectsDefaults.set(data, forKey: recentProjectAccessDefaultsKey)
        } catch {
            recentProjectsDefaults.removeObject(forKey: recentProjectAccessDefaultsKey)
        }
    }

    private func resolveProjectURL(_ url: URL) throws -> URL {
        let standardizedURL = url.standardizedFileURL
        guard let bookmarkData = Self.recentProjectRecords(defaults: recentProjectsDefaults)
            .first(where: { $0.path == standardizedURL.path })?
            .bookmarkData else {
            return standardizedURL
        }
        var isStale = false
        let resolvedURL = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ).standardizedFileURL
        if isStale {
            rememberProjectURL(resolvedURL)
        }
        return resolvedURL
    }

    private func beginProjectAccess(_ url: URL) {
        endProjectAccess()
        currentProjectAccessURL = url
        currentProjectAccessIsScoped = url.startAccessingSecurityScopedResource()
    }

    private func endProjectAccess() {
        guard currentProjectAccessIsScoped, let currentProjectAccessURL else {
            currentProjectAccessURL = nil
            currentProjectAccessIsScoped = false
            return
        }
        currentProjectAccessURL.stopAccessingSecurityScopedResource()
        self.currentProjectAccessURL = nil
        currentProjectAccessIsScoped = false
    }

    private func endModelBundleAccess() {
        guard currentModelBundleAccessIsScoped, let currentModelBundleAccessURL else {
            currentModelBundleAccessURL = nil
            currentModelBundleAccessIsScoped = false
            return
        }
        currentModelBundleAccessURL.stopAccessingSecurityScopedResource()
        self.currentModelBundleAccessURL = nil
        currentModelBundleAccessIsScoped = false
    }

    private func makeSecurityScopedBookmarkData(for url: URL) -> Data? {
        let accessStarted = url.startAccessingSecurityScopedResource()
        defer {
            if accessStarted {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            return try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            return nil
        }
    }

    private static func recentProjectRecords(defaults: UserDefaults) -> [RecentProjectAccessRecord] {
        guard let data = defaults.data(forKey: recentProjectAccessDefaultsKey) else {
            return []
        }
        do {
            return try PropertyListDecoder().decode([RecentProjectAccessRecord].self, from: data)
        } catch {
            return []
        }
    }

    private nonisolated static func makeAndWriteProjectPackage(
        projectName: String,
        targetURL: URL,
        temporaryURL: URL,
        template: LearningProjectTemplate
    ) throws -> KuyuProjectPackage {
        guard !FileManager.default.fileExists(atPath: targetURL.path) else {
            throw KuyuProjectPackageError.packageAlreadyExists(path: targetURL.path)
        }
        let package = try KuyuProjectFactory().makeRunnableStarterProject(
            rootURL: temporaryURL,
            name: projectName,
            template: template
        )
        try KuyuProjectPackageWriter().write(package)
        return package
    }

    private func cleanupTemporaryProject(at temporaryURL: URL, primaryError: Error) {
        guard FileManager.default.fileExists(atPath: temporaryURL.path) else {
            projectCreationError = AppViewModelErrorFormatter.message(for: primaryError)
            return
        }
        do {
            try FileManager.default.removeItem(at: temporaryURL)
            projectCreationError = AppViewModelErrorFormatter.message(for: primaryError)
        } catch {
            projectCreationError = AppViewModelErrorFormatter.message(
                for: AppViewModelError.projectCreationCleanupFailed(
                    primary: AppViewModelErrorFormatter.message(for: primaryError),
                    cleanup: AppViewModelErrorFormatter.message(for: error)
                )
            )
        }
    }

    private func cleanupTemporaryProjectWithoutPublishing(at temporaryURL: URL) {
        guard FileManager.default.fileExists(atPath: temporaryURL.path) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: temporaryURL)
            inactiveProjectCleanupError = nil
        } catch {
            inactiveProjectCleanupError = AppViewModelErrorFormatter.message(for: error)
        }
    }

    private func projectCreationSessionIsActive(_ sessionID: UUID) -> Bool {
        projectCreationSessionID == sessionID
    }

    private func finishProjectCreationSessionIfActive(_ sessionID: UUID) {
        guard projectCreationSessionIsActive(sessionID) else {
            return
        }
        isCreatingProject = false
        projectCreationTask = nil
        projectCreationSessionID = nil
    }
}

private let recentProjectAccessDefaultsKey = "team.stamp.Bounded.recentProjectAccess"

private struct RecentProjectAccessRecord: Codable, Sendable, Equatable {
    let path: String
    let bookmarkData: Data

    func resolvedURL() -> URL {
        var isStale = false
        do {
            return try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
    }
}

private enum AppViewModelError: Error, Sendable {
    case projectCreationCancelled
    case projectCreationCleanupFailed(primary: String, cleanup: String)
    case unreadableModelBundle(String)
    case unsupportedFileType(String)
}

private enum AppViewModelErrorFormatter {
    static func message(for error: Error) -> String {
        switch error {
        case AppViewModelError.projectCreationCancelled:
            return "Project creation was cancelled."
        case let AppViewModelError.projectCreationCleanupFailed(primary, cleanup):
            return "Project creation failed. \(primary) Cleanup also failed. \(cleanup)"
        case let AppViewModelError.unreadableModelBundle(path):
            return "Model bundle is not readable: \(path)"
        case let AppViewModelError.unsupportedFileType(name):
            return "Unsupported file type: \(name)"
        case let packageError as KuyuProjectPackageError:
            return message(for: packageError)
        case let sessionError as KuyuProjectSessionError:
            return sessionError.description
        default:
            return String(describing: error)
        }
    }

    private static func message(for error: KuyuProjectPackageError) -> String {
        switch error {
        case let .invalidPackageExtension(path):
            return "Project package must use the .kuyu extension: \(path)"
        case let .packageAlreadyExists(path):
            return "A project already exists at: \(path)"
        case let .missingProjectManifest(path):
            return "Project manifest is missing: \(path)"
        case let .schemaVersionMismatch(file, expected, actual):
            return "Project file schema mismatch in \(file). Expected \(expected), found \(actual)."
        case let .emptyField(file, field):
            return "Project file \(file) has an empty required field: \(field)."
        case let .missingReference(file, value):
            return "Project file \(file) references missing value: \(value)."
        case let .mismatchedReference(file, field, expected, actual):
            return "Project file \(file) has mismatched \(field). Expected \(expected), found \(actual)."
        case let .invalidTemplate(error):
            return "Project template is invalid: \(error.description)"
        }
    }
}
