import Foundation
import KuyuCore

public struct KuyAtt1LogWriter {
    public enum WriterError: Error, Equatable {
        case invalidDirectory
    }

    public var store: LogStore
    public var fileNames: LogFileNames

    public init(store: LogStore = LogStore(), fileNames: LogFileNames = LogFileNames()) {
        self.store = store
        self.fileNames = fileNames
    }

    public func write(output: KuyAtt1RunOutput, to directory: URL) throws -> ScenarioLogBundle {
        try store.ensureDirectory(directory)

        let summaryURL = directory.appendingPathComponent(fileNames.summary)
        let manifestURL = directory.appendingPathComponent(fileNames.manifest)
        let evaluationsURL = directory.appendingPathComponent(fileNames.evaluations)
        let replayURL = directory.appendingPathComponent(fileNames.replay)

        try store.write(output.summary, to: summaryURL)
        try store.write(output.summary.manifest, to: manifestURL)
        try store.write(output.summary.evaluations, to: evaluationsURL)
        try store.write(output.summary.replayChecks, to: replayURL)

        var logIndex: [ScenarioLogIndex] = []
        for entry in output.logs {
            let scenarioId = entry.key.scenarioId
            let seed = entry.key.seed
            let fileName = "\(scenarioId.rawValue.replacingOccurrences(of: "/", with: "_"))_seed_\(seed.rawValue)_log.json"
            let logURL = directory.appendingPathComponent(fileName)
            try store.write(entry.log, to: logURL)
            logIndex.append(ScenarioLogIndex(scenarioId: scenarioId, seed: seed, fileName: fileName))
        }

        let bundle = ScenarioLogBundle(
            summary: output.summary,
            manifest: output.summary.manifest,
            evaluations: output.summary.evaluations,
            replayChecks: output.summary.replayChecks,
            logs: logIndex.sorted { $0.fileName < $1.fileName }
        )
        let bundleURL = directory.appendingPathComponent("bundle.json")
        try store.write(bundle, to: bundleURL)
        return bundle
    }
}
