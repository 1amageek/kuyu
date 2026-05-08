import Foundation

public struct LearningStarterProject: Sendable, Equatable {
    public let projectRoot: URL
    public let sourceCheckpoint: URL
    public let artifactRoot: URL

    public init(projectRoot: URL, sourceCheckpoint: URL, artifactRoot: URL) {
        self.projectRoot = projectRoot
        self.sourceCheckpoint = sourceCheckpoint
        self.artifactRoot = artifactRoot
    }
}
