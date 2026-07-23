import Foundation

actor LearningCampaignRunStoreLoader {
    private let store: LearningCampaignRunStore
    private var progressReader = LearningCampaignProgressJournalReader()

    init(store: LearningCampaignRunStore = LearningCampaignRunStore()) {
        self.store = store
    }

    func load(
        from artifactDirectory: URL,
        previousState: LearningCampaignRunStoreState?,
        hadError: Bool,
        formatsRunLog: Bool
    ) throws -> LearningCampaignArtifactLoad? {
        try Task.checkCancellation()
        let progress = try progressReader.read(
            from: artifactDirectory.appendingPathComponent("progress.jsonl")
        )
        try Task.checkCancellation()
        let state = try store.load(
            from: artifactDirectory,
            progressEvents: progress.records
        )
        try Task.checkCancellation()
        if !hadError, let previousState, state == previousState {
            return nil
        }
        let runLog = formatsRunLog
            ? LearningCampaignRunLogFormatter.entries(from: state)
            : nil
        try Task.checkCancellation()
        return LearningCampaignArtifactLoad(state: state, runLog: runLog)
    }
}
