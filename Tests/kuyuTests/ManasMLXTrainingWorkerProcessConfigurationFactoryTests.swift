import Foundation
import KuyuTraining
import KuyuWorkerRuntime
import Testing

@Suite("Manas MLX worker process configuration")
struct ManasMLXTrainingWorkerProcessConfigurationFactoryTests {
    @Test(.timeLimit(.minutes(1)))
    func resolvesTheMLXResourceBundleBesideTheExecutable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mlx-worker-configuration-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executableURL = root.appendingPathComponent("kuyu", isDirectory: false)
        try Data("executable".utf8).write(to: executableURL)
        let resourceBundle = root.appendingPathComponent(
            ManasMLXTrainingWorkerProcessConfigurationFactory.mlxResourceBundleName,
            isDirectory: true
        )
        let resourceDirectory = resourceBundle
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
        try FileManager.default.createDirectory(
            at: resourceDirectory,
            withIntermediateDirectories: true
        )
        try Data("metal".utf8).write(
            to: resourceDirectory.appendingPathComponent(
                "default.metallib",
                isDirectory: false
            )
        )

        let configuration = try ManasMLXTrainingWorkerProcessConfigurationFactory()
            .configuration(
                executableURL: executableURL,
                launchRootDirectory: root.appendingPathComponent("launches", isDirectory: true)
            )

        #expect(configuration.resourceBundles == [
            TrainingRunWorkerResourceBundle(sourceURL: resourceBundle)
        ])
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsAnExecutableWithoutTheMLXResourceBundle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "mlx-worker-configuration-missing-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executableURL = root.appendingPathComponent("kuyu", isDirectory: false)
        try Data("executable".utf8).write(to: executableURL)

        #expect(
            throws: ManasMLXTrainingWorkerProcessConfigurationFactory.FactoryError.self
        ) {
            _ = try ManasMLXTrainingWorkerProcessConfigurationFactory().configuration(
                executableURL: executableURL,
                launchRootDirectory: root.appendingPathComponent("launches", isDirectory: true)
            )
        }
    }
}
