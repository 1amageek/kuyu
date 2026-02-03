public struct LogFileNames {
    public let summary: String
    public let manifest: String
    public let evaluations: String
    public let replay: String

    public init(
        summary: String = "summary.json",
        manifest: String = "manifest.json",
        evaluations: String = "evaluations.json",
        replay: String = "replay.json"
    ) {
        self.summary = summary
        self.manifest = manifest
        self.evaluations = evaluations
        self.replay = replay
    }
}
