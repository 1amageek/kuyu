import Foundation

public struct TrainingDatasetExporter {
    public init() {}

    @discardableResult
    public func write(output: KuyAtt1RunOutput, to directory: URL) throws -> [ScenarioKey: URL] {
        try write(entries: output.logs, to: directory)
    }

    @discardableResult
    public func write(entries: [ScenarioLogEntry], to directory: URL) throws -> [ScenarioKey: URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let writer = TrainingDatasetWriter()
        var outputs: [ScenarioKey: URL] = [:]

        for entry in entries {
            let subdir = directory.appendingPathComponent(subdirectoryName(for: entry.key), isDirectory: true)
            let url = try writer.write(log: entry.log, to: subdir)
            outputs[entry.key] = url
        }

        return outputs
    }

    private func subdirectoryName(for key: ScenarioKey) -> String {
        let raw = key.scenarioId.rawValue
        let sanitized = raw
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        return "\(sanitized)_seed_\(key.seed.rawValue)"
    }
}
