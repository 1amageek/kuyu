import Foundation
import KuyuMLXCampaignContracts
import KuyuTraining

struct LearningCampaignRunLogRecord: Identifiable, Sendable, Equatable {
    enum Category: String, Sendable, Equatable {
        case lifecycle
        case preflight
        case checkpointEvaluation
        case regression
        case seed
        case generation
        case candidate
        case artifact
        case diagnostics
    }

    enum Level: String, Sendable, Equatable {
        case info
        case success
        case warning
        case failure
    }

    let id: UUID
    let timestamp: Date
    let category: Category
    let level: Level
    let phase: String
    let title: String
    let detail: String
    let metadata: [String]

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        category: Category,
        level: Level = .info,
        phase: String,
        title: String,
        detail: String = "",
        metadata: [String] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.level = level
        self.phase = phase
        self.title = title
        self.detail = detail
        self.metadata = metadata
    }
}

enum LearningCampaignRunLogFormatter {
    static func entry(
        from event: TrainingRunLogEvent,
        progress: Progress
    ) -> LearningCampaignRunLogRecord {
        let progressText = event.progressFraction
            .map { String(format: "%.0f%%", $0 * 100) }
            ?? String(format: "%.0f%%", progress.fractionCompleted * 100)
        var metadata = event.metadata
            .sorted { lhs, rhs in lhs.key < rhs.key }
            .map { key, value in "\(key) \(value)" }
        if let seed = event.seed {
            metadata.append("seed \(seed)")
        }
        if let generationIndex = event.generationIndex {
            metadata.append("generation \(generationIndex)")
        }
        if let candidateID = event.candidateID {
            metadata.append("candidate \(candidateID)")
        }
        metadata.append("progress \(progressText)")
        return LearningCampaignRunLogRecord(
            timestamp: event.timestamp,
            category: category(from: event.phase),
            level: level(from: event.level),
            phase: event.phase,
            title: event.message,
            detail: detail(from: event),
            metadata: metadata
        )
    }

    private static func category(from phase: String) -> LearningCampaignRunLogRecord.Category {
        switch phase {
        case "preflight":
            return .preflight
        case "checkpoint-evaluation":
            return .checkpointEvaluation
        case "regression":
            return .regression
        case "seed":
            return .seed
        case "generation":
            return .generation
        case "candidate":
            return .candidate
        case "artifact":
            return .artifact
        case "failed":
            return .diagnostics
        default:
            return .lifecycle
        }
    }

    private static func level(from level: TrainingRunLogLevel) -> LearningCampaignRunLogRecord.Level {
        switch level {
        case .info:
            return .info
        case .success:
            return .success
        case .warning:
            return .warning
        case .failure:
            return .failure
        }
    }

    private static func detail(from event: TrainingRunLogEvent) -> String {
        guard event.phase == "candidate" else {
            return event.metadata["failureReasons"] ?? event.metadata["path"] ?? event.metadata["checkpoint"] ?? ""
        }
        var parts: [String] = []
        if let fitness = event.metadata["fitness"] {
            parts.append("fitness \(fitness)")
        }
        if let reward = event.metadata["reward"] {
            parts.append("reward \(reward)")
        }
        if let passRate = event.metadata["taskPassRate"] {
            parts.append("pass \(passRate)")
        }
        if let holdTimeRatio = event.metadata["holdTimeRatio"] {
            parts.append("hold \(holdTimeRatio)")
        }
        if let altitudeErrorRatio = event.metadata["altitudeErrorRatio"] {
            parts.append("altitudeError \(altitudeErrorRatio)")
        }
        let execution = executionDetail(metadata: event.metadata)
        if !execution.isEmpty {
            parts.append(execution)
        }
        if let reasons = event.metadata["failureReasons"], !reasons.isEmpty {
            parts.append("reasons \(reasons)")
        }
        return parts.joined(separator: ", ")
    }

    private static func executionDetail(metadata: [String: String]) -> String {
        var parts: [String] = []
        if let gpu = metadata["gpu"] {
            parts.append(gpu == "true" ? "GPU" : "CPU")
        }
        if let tensorWorld = metadata["tensorWorld"] {
            parts.append(tensorWorld == "true" ? "tensor world" : "isolated world")
        }
        if let summary = metadata["summary"] {
            parts.append("\(summary) summary")
        }
        if let population = metadata["population"] {
            parts.append("population \(population)")
        }
        if let worlds = metadata["worlds"] {
            parts.append("worlds \(worlds)")
        }
        if let history = metadata["history"],
           let observation = metadata["obs"],
           let action = metadata["action"] {
            parts.append("obs [\(history),\(observation)] action \(action)")
        }
        return parts.isEmpty ? "" : "execution \(parts.joined(separator: " / "))"
    }

    static func entries(from state: LearningCampaignRunStoreState) -> [LearningCampaignRunLogRecord] {
        var entries: [LearningCampaignRunLogRecord] = []
        entries.append(contentsOf: state.progressEvents.map(progressEntry))
        entries.append(contentsOf: state.generations.flatMap { generation in
            generationEntries(generation, candidates: state.candidates(seed: generation.seed, generationIndex: generation.generationIndex))
        })
        if let reason = state.primaryFailureReason {
            entries.append(LearningCampaignRunLogRecord(
                timestamp: Date(),
                category: .diagnostics,
                level: .warning,
                phase: "diagnostics",
                title: "Primary issue",
                detail: reason
            ))
        }
        return entries.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
            return lhs.title < rhs.title
        }
    }

    static func transcript(entries: [LearningCampaignRunLogRecord]) -> String {
        entries.map { entry in
            let metadata = entry.metadata.isEmpty ? "" : " [\(entry.metadata.joined(separator: ", "))]"
            let detail = entry.detail.isEmpty ? "" : " - \(entry.detail)"
            return "\(isoFormatStyle.format(entry.timestamp)) \(entry.level.rawValue.uppercased()) \(entry.phase): \(entry.title)\(detail)\(metadata)"
        }
        .joined(separator: "\n")
    }

    private static func progressEntry(_ record: LearningCampaignProgressEvent) -> LearningCampaignRunLogRecord {
        let phase = record.phase ?? record.status ?? "campaign"
        let detail = progressDetail(record)
        let metadata = progressMetadata(record)
        return LearningCampaignRunLogRecord(
            id: UUID(uuidString: deterministicID("\(record.timestamp.timeIntervalSince1970)|\(record.event)")) ?? UUID(),
            timestamp: record.timestamp,
            category: progressCategory(record),
            level: progressLevel(record),
            phase: phase,
            title: record.event,
            detail: detail,
            metadata: metadata
        )
    }

    private static func progressLevel(_ record: LearningCampaignProgressEvent) -> LearningCampaignRunLogRecord.Level {
        if let exitCode = record.exitCode {
            return exitCode == 0 ? .success : .failure
        }
        switch record.status {
        case "succeeded", "accepted":
            return .success
        case "rejected", "cancelled":
            return .warning
        case "failed":
            return .failure
        default:
            return .info
        }
    }

    private static func progressCategory(_ record: LearningCampaignProgressEvent) -> LearningCampaignRunLogRecord.Category {
        switch record.event {
        case "preflight-started", "preflight-completed":
            return .preflight
        case "parent-evaluation-started", "parent-evaluation-completed":
            return .checkpointEvaluation
        case "checkpoint-regression-started", "checkpoint-regression-completed":
            return .regression
        case "seed-started", "seed-completed":
            return .seed
        case "generation-started", "generation-completed":
            return .generation
        case "candidate-evaluated":
            return .candidate
        case "artifact-written":
            return .artifact
        case "campaign-failed", "validation-failed":
            return .diagnostics
        default:
            return .lifecycle
        }
    }

    private static func progressDetail(_ record: LearningCampaignProgressEvent) -> String {
        if let message = record.message, !message.isEmpty {
            return message
        }
        if let fitness = record.fitness {
            var parts = [String(format: "fitness %.3f", fitness)]
            if let reward = record.rewardAverage {
                parts.append(String(format: "reward %.3f", reward))
            }
            if let taskPassRate = record.taskPassRate {
                parts.append(String(format: "pass %.0f%%", taskPassRate * 100))
            }
            if let holdTimeRatio = record.holdTimeRatio {
                parts.append(String(format: "hold %.0f%%", holdTimeRatio * 100))
            }
            if let altitudeErrorRatio = record.altitudeErrorRatio {
                parts.append(String(format: "altitudeError %.2f", altitudeErrorRatio))
            }
            if let safetyViolationRate = record.safetyViolationRate {
                parts.append(String(format: "safety %.0f%%", safetyViolationRate * 100))
            }
            let execution = executionDetail(record)
            if !execution.isEmpty {
                parts.append(execution)
            }
            if !record.failureReasons.isEmpty {
                parts.append("reasons \(record.failureReasons.joined(separator: ","))")
            }
            return parts.joined(separator: ", ")
        }
        if let bestCandidateID = record.bestCandidateID {
            return "best candidate \(bestCandidateID)"
        }
        if let exitCode = record.exitCode {
            return "exitCode \(exitCode)"
        }
        return record.path ?? ""
    }

    private static func progressMetadata(_ record: LearningCampaignProgressEvent) -> [String] {
        var metadata: [String] = []
        if let status = record.status {
            metadata.append("status \(status)")
        }
        if let seed = record.seed {
            metadata.append("seed \(seed)")
        }
        if let generationIndex = record.generationIndex {
            metadata.append("generation \(generationIndex)")
        }
        if let candidateID = record.candidateID {
            metadata.append("candidate \(candidateID)")
        }
        if let accepted = record.accepted {
            metadata.append(accepted ? "accepted" : "not accepted")
        }
        if let throughput = record.workerThroughput {
            metadata.append(String(format: "throughput %.2f/s", throughput))
        }
        if let gpu = record.gpuAcceleration {
            metadata.append(gpu ? "gpu" : "cpu")
        }
        if let tensorWorld = record.tensorWorldBatch {
            metadata.append(tensorWorld ? "tensor world" : "isolated worlds")
        }
        if let tensorSummary = record.tensorSummary {
            metadata.append(tensorSummary ? "tensor summary" : "materialized summary")
        }
        if let population = record.vectorizedPopulationSize {
            metadata.append("population \(population)")
        }
        if let worlds = record.vectorizedWorldCount {
            metadata.append("worlds \(worlds)")
        }
        if let history = record.vectorizedHistoryLength,
           let observation = record.vectorizedObservationDimension,
           let action = record.vectorizedActionDimension {
            metadata.append("shape [\(history),\(observation)] -> \(action)")
        }
        if let path = record.path, record.message != nil {
            metadata.append(path)
        }
        return metadata
    }

    private static func executionDetail(_ record: LearningCampaignProgressEvent) -> String {
        var parts: [String] = []
        if let gpu = record.gpuAcceleration {
            parts.append(gpu ? "GPU" : "CPU")
        }
        if let tensorWorld = record.tensorWorldBatch {
            parts.append(tensorWorld ? "tensor world" : "isolated world")
        }
        if let tensorSummary = record.tensorSummary {
            parts.append(tensorSummary ? "tensor summary" : "materialized summary")
        }
        if let population = record.vectorizedPopulationSize {
            parts.append("population \(population)")
        }
        if let worlds = record.vectorizedWorldCount {
            parts.append("worlds \(worlds)")
        }
        if let history = record.vectorizedHistoryLength,
           let observation = record.vectorizedObservationDimension,
           let action = record.vectorizedActionDimension {
            parts.append("obs [\(history),\(observation)] action \(action)")
        }
        return parts.isEmpty ? "" : "execution \(parts.joined(separator: " / "))"
    }

    private static func generationEntries(
        _ generation: LearningCampaignGenerationState,
        candidates: [LearningCampaignCandidateState]
    ) -> [LearningCampaignRunLogRecord] {
        var entries: [LearningCampaignRunLogRecord] = candidates.map { candidate in
            LearningCampaignRunLogRecord(
                timestamp: generation.createdAt,
                category: .candidate,
                level: candidate.taskPassRate == 1 ? .success : .info,
                phase: "generation \(candidate.generationIndex)",
                title: "Candidate \(candidate.candidateID)",
                detail: candidateDetail(candidate),
                metadata: ["seed \(candidate.seed)"]
            )
        }
        entries.append(LearningCampaignRunLogRecord(
            timestamp: generation.createdAt,
            category: .generation,
            level: generation.accepted ? .success : (generation.incumbentImproved ? .info : .warning),
            phase: "generation \(generation.generationIndex)",
            title: generation.accepted ? "Generation accepted checkpoint" : "Generation completed",
            detail: generationDetail(generation),
            metadata: ["seed \(generation.seed)"]
        ))
        return entries
    }

    private static func candidateDetail(_ candidate: LearningCampaignCandidateState) -> String {
        var parts: [String] = []
        if let value = candidate.scalarFitness {
            parts.append(String(format: "fitness %.3f", value))
        }
        if let value = candidate.rewardAverage {
            parts.append(String(format: "reward %.3f", value))
        }
        if let value = candidate.taskPassRate {
            parts.append(String(format: "pass %.0f%%", value * 100))
        }
        if let value = candidate.holdTimeRatio {
            parts.append(String(format: "hold %.0f%%", value * 100))
        }
        if let value = candidate.altitudeErrorRatio {
            parts.append(String(format: "altitudeError %.2f", value))
        }
        if let duration = candidate.durationSeconds {
            parts.append(String(format: "duration %.2fs", duration))
        }
        if candidate.isIncumbent {
            parts.append("incumbent")
        }
        return parts.isEmpty ? "No candidate metrics recorded." : parts.joined(separator: ", ")
    }

    private static func generationDetail(_ generation: LearningCampaignGenerationState) -> String {
        var parts: [String] = []
        if let candidate = generation.bestCandidateID {
            parts.append("best \(candidate)")
        }
        if let value = generation.bestFitness {
            parts.append(String(format: "bestFitness %.3f", value))
        }
        if let value = generation.bestVsIncumbentDelta {
            parts.append(String(format: "delta %+.6f", value))
        }
        if !generation.rejectionReasons.isEmpty {
            parts.append("reasons \(generation.rejectionReasons.joined(separator: ", "))")
        }
        return parts.isEmpty ? "No generation metrics recorded." : parts.joined(separator: ", ")
    }

    private static func deterministicID(_ value: String) -> String {
        let hash = UInt(bitPattern: value.hashValue)
        let rawSuffix = String(hash % 1_000_000_000_000)
        let padding = String(repeating: "0", count: max(0, 12 - rawSuffix.count))
        return "00000000-0000-0000-0000-\(padding)\(rawSuffix)"
    }

    // A shared Sendable format style avoids a per-record formatter allocation
    // when formatting large progress logs. The default style matches
    // ISO8601DateFormatter's .withInternetDateTime output.
    private static let isoFormatStyle = Date.ISO8601FormatStyle()

}
