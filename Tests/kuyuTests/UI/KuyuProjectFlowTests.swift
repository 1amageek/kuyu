import Foundation
import KuyuTraining
import Testing
@testable import KuyuUI

@MainActor
@Test(.timeLimit(.minutes(1))) func appViewModelCreatesAndOpensDesignOnlyKuyuProject() throws {
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
        template: .droneLiftStarter
    )
    try KuyuProjectPackageWriter().write(package)

    let model = AppViewModel(logStore: UILogStore(buffer: UILogBuffer()))
    model.openProject(at: projectURL)

    #expect(model.currentProject == nil)
    #expect(model.projectCreationError?.contains("Missing source model bundle") == true)
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
