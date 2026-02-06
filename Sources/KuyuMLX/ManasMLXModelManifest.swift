import Foundation
import ManasMLXModels

public struct ManasMLXModelManifest: Codable, Sendable, Equatable {
    public let formatVersion: Int
    public let name: String
    public let createdAt: Date
    public let lastTrainedAt: Date?
    public let coreConfig: ManasMLXCoreConfig
    public let reflexConfig: ManasMLXReflexConfig?

    public init(
        formatVersion: Int = 1,
        name: String,
        createdAt: Date,
        lastTrainedAt: Date?,
        coreConfig: ManasMLXCoreConfig,
        reflexConfig: ManasMLXReflexConfig?
    ) {
        self.formatVersion = formatVersion
        self.name = name
        self.createdAt = createdAt
        self.lastTrainedAt = lastTrainedAt
        self.coreConfig = coreConfig
        self.reflexConfig = reflexConfig
    }
}
