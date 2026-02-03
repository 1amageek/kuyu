import Foundation
import KuyuCore

struct RunRecord: Identifiable {
    let id: UUID
    let timestamp: Date
    let output: KuyAtt1RunOutput
    let scenarios: [ScenarioRunRecord]

    init(id: UUID = UUID(), timestamp: Date = Date(), output: KuyAtt1RunOutput, scenarios: [ScenarioRunRecord]) {
        self.id = id
        self.timestamp = timestamp
        self.output = output
        self.scenarios = scenarios
    }
}
