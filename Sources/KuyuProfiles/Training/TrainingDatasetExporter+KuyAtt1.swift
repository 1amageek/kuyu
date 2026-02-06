import Foundation
import KuyuCore

public extension TrainingDatasetExporter {
    @discardableResult
    func write(output: KuyAtt1RunOutput, to directory: URL) throws -> [ScenarioKey: URL] {
        try write(entries: output.logs, to: directory)
    }
}
