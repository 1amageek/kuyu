import Foundation
import KuyuCore
import KuyuProfiles

public struct RunRecord: Identifiable {
    public let id: UUID
    let timestamp: Date
    let output: KuyAtt1RunOutput
    let scenarios: [ScenarioRunRecord]

    public init(id: UUID = UUID(), timestamp: Date = Date(), output: KuyAtt1RunOutput, scenarios: [ScenarioRunRecord]) {
        self.id = id
        self.timestamp = timestamp
        self.output = output
        self.scenarios = scenarios
    }
}
