import Foundation

struct TrainingTimelineEntry: Identifiable, Hashable, Sendable {
    let id: UUID
    let timestamp: Date
    let phase: TrainingLiveStatus.Phase
    let message: String
    let iteration: Int

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        phase: TrainingLiveStatus.Phase,
        message: String,
        iteration: Int
    ) {
        self.id = id
        self.timestamp = timestamp
        self.phase = phase
        self.message = message
        self.iteration = iteration
    }
}

