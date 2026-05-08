import Foundation
import KuyuMLX
import KuyuTraining

public struct LearningCampaignProgressRecord: Codable, Sendable, Equatable {
    public let event: String
    public let timestamp: String
    public let status: String?
    public let exitCode: Int?

    public init(event: String, timestamp: String, status: String?, exitCode: Int?) {
        self.event = event
        self.timestamp = timestamp
        self.status = status
        self.exitCode = exitCode
    }
}

public struct LearningCampaignGenerationState: Identifiable, Sendable, Equatable {
    public let id: String
    public let seed: String
    public let generationIndex: Int
    public let accepted: Bool
    public let incumbentImproved: Bool
    public let bestCandidateID: String?
    public let bestFitness: Double?
    public let incumbentFitness: Double?
    public let bestVsIncumbentDelta: Double?
    public let minimumImprovementOverIncumbent: Double?
    public let mutationRate: Double
    public let mutationNoiseScale: Double
    public let rejectionReasons: [String]
    public let createdAt: Date

    init(seed: String, record: PopulationGenerationRecord) {
        self.id = "\(seed)-\(record.runID)-\(record.generationIndex)"
        self.seed = seed
        self.generationIndex = record.generationIndex
        self.accepted = record.accepted
        self.incumbentImproved = record.incumbentImproved
        self.bestCandidateID = record.bestCandidateID
        self.bestFitness = record.bestFitness
        self.incumbentFitness = record.incumbentFitness
        self.bestVsIncumbentDelta = record.bestVsIncumbentDelta
        self.minimumImprovementOverIncumbent = record.minimumImprovementOverIncumbent
        self.mutationRate = record.mutationRate
        self.mutationNoiseScale = record.mutationNoiseScale
        self.rejectionReasons = record.rejectionReasons
        self.createdAt = record.createdAt
    }
}

public struct LearningCampaignRunStoreState: Sendable, Equatable {
    public let artifactDirectory: URL
    public let plan: LearningCampaignPlan?
    public let status: LearningCampaignStatus?
    public let summary: LearningCampaignSummary?
    public let validation: LearningCampaignValidation?
    public let retention: LearningCampaignArtifactRetentionSummary?
    public let progressEvents: [LearningCampaignProgressRecord]
    public let generations: [LearningCampaignGenerationState]

    public var latestEvent: LearningCampaignProgressRecord? {
        progressEvents.last
    }

    public var task: String {
        plan?.task ?? "--"
    }

    public var suiteSummary: String {
        guard let plan else { return "--" }
        return plan.suites.joined(separator: ",")
    }

    public var seedCount: Int {
        summary?.seedCount ?? plan?.seeds.count ?? 0
    }

    public var acceptedCount: Int {
        summary?.acceptedCount ?? generations.filter(\.accepted).count
    }

    public var finalCheckpoint: String? {
        summary?.finalCheckpoint
    }

    public var statusLabel: String {
        status?.status ?? latestEvent?.status ?? "running"
    }

    public var validationLabel: String {
        guard let validation else { return "--" }
        return validation.valid ? "valid" : "invalid"
    }

    public var bestDelta: Double? {
        let deltas = generations.compactMap(\.bestVsIncumbentDelta)
        return deltas.max()
    }

    public var latestGenerations: [LearningCampaignGenerationState] {
        generations
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                if lhs.seed != rhs.seed { return lhs.seed < rhs.seed }
                return lhs.generationIndex > rhs.generationIndex
            }
    }

    public var isActive: Bool {
        let label = statusLabel.lowercased()
        return label == "running" || label == "started"
    }
}

public struct LearningCampaignRunStore {
    public init() {}

    public func load(from artifactDirectory: URL) throws -> LearningCampaignRunStoreState {
        let plan: LearningCampaignPlan? = try decodeIfPresent(
            LearningCampaignPlan.self,
            from: artifactDirectory.appendingPathComponent("learning-campaign-plan.json")
        )
        let status: LearningCampaignStatus? = try decodeIfPresent(
            LearningCampaignStatus.self,
            from: artifactDirectory.appendingPathComponent("campaign-status.json")
        )
        let summary: LearningCampaignSummary? = try decodeIfPresent(
            LearningCampaignSummary.self,
            from: artifactDirectory.appendingPathComponent("learning-campaign-summary.json")
        )
        let validation: LearningCampaignValidation? = try decodeIfPresent(
            LearningCampaignValidation.self,
            from: artifactDirectory.appendingPathComponent("learning-campaign-validation.json")
        )
        let retention: LearningCampaignArtifactRetentionSummary? = try decodeIfPresent(
            LearningCampaignArtifactRetentionSummary.self,
            from: artifactDirectory.appendingPathComponent("artifact-retention.json")
        )

        return LearningCampaignRunStoreState(
            artifactDirectory: artifactDirectory,
            plan: plan,
            status: status,
            summary: summary,
            validation: validation,
            retention: retention ?? summary?.retention,
            progressEvents: try decodeJSONLines(
                LearningCampaignProgressRecord.self,
                from: artifactDirectory.appendingPathComponent("progress.jsonl")
            ),
            generations: try loadGenerations(from: artifactDirectory)
        )
    }

    private func loadGenerations(from artifactDirectory: URL) throws -> [LearningCampaignGenerationState] {
        let seedsRoot = artifactDirectory.appendingPathComponent("seeds", isDirectory: true)
        guard FileManager.default.fileExists(atPath: seedsRoot.path) else { return [] }

        let seedDirectories = try FileManager.default.contentsOfDirectory(
            at: seedsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var states: [LearningCampaignGenerationState] = []
        for seedDirectory in seedDirectories {
            guard try isDirectory(seedDirectory) else { continue }
            let records = try decodeJSONLines(
                PopulationGenerationRecord.self,
                from: seedDirectory
                    .appendingPathComponent("evolution", isDirectory: true)
                    .appendingPathComponent("generations.jsonl")
            )
            let seed = seedDirectory.lastPathComponent
            states.append(contentsOf: records.map { LearningCampaignGenerationState(seed: seed, record: $0) })
        }
        return states.sorted { lhs, rhs in
            if lhs.seed != rhs.seed { return lhs.seed < rhs.seed }
            return lhs.generationIndex < rhs.generationIndex
        }
    }

    private func decodeIfPresent<T: Decodable>(_ type: T.Type, from url: URL) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try decoder.decode(type, from: data)
    }

    private func decodeJSONLines<T: Decodable>(_ type: T.Type, from url: URL) throws -> [T] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let text = try String(contentsOf: url, encoding: .utf8)
        var records: [T] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let data = Data(trimmed.utf8)
            records.append(try decoder.decode(type, from: data))
        }
        return records
    }

    private func isDirectory(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        return values.isDirectory == true
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        return decoder
    }
}
