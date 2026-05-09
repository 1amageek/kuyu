import Foundation

public final class LearningCampaignRunContext: Sendable {
    private let handle: LearningCampaignRunHandle

    public init(handle: LearningCampaignRunHandle) {
        self.handle = handle
    }

    public func emit(_ event: LearningCampaignRunEvent) async {
        Task { @MainActor [handle] in
            handle.emit(event)
        }
    }

    public func advanceProgress(by units: Int64 = 1, description: String? = nil) async {
        Task { @MainActor [handle] in
            if let description {
                handle.progress.localizedDescription = description
            }
            let next = min(handle.progress.completedUnitCount + max(0, units), handle.progress.totalUnitCount)
            handle.progress.completedUnitCount = next
        }
    }

    public func finishProgress(description: String? = nil) async {
        Task { @MainActor [handle] in
            if let description {
                handle.progress.localizedDescription = description
            }
            handle.progress.completedUnitCount = handle.progress.totalUnitCount
        }
    }

    public func checkCancellation() async throws {
        try Task.checkCancellation()
    }
}
