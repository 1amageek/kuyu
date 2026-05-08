import Foundation

@MainActor
public final class LearningCampaignRunContext {
    private let handle: LearningCampaignRunHandle

    public init(handle: LearningCampaignRunHandle) {
        self.handle = handle
    }

    public var progress: Progress {
        handle.progress
    }

    public func emit(_ event: LearningCampaignRunEvent) {
        handle.emit(event)
    }

    public func advanceProgress(by units: Int64 = 1, description: String? = nil) {
        if let description {
            progress.localizedDescription = description
        }
        let next = min(progress.completedUnitCount + max(0, units), progress.totalUnitCount)
        progress.completedUnitCount = next
    }

    public func finishProgress(description: String? = nil) {
        if let description {
            progress.localizedDescription = description
        }
        progress.completedUnitCount = progress.totalUnitCount
    }

    public func checkCancellation() throws {
        if progress.isCancelled || Task.isCancelled {
            throw CancellationError()
        }
    }
}

