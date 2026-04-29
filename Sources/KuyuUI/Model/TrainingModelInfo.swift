import Foundation

struct TrainingModelInfo: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var createdAt: Date
    var lastTrainedAt: Date?
    var hasSupervisedBootstrap: Bool
    var storageURL: URL
}
