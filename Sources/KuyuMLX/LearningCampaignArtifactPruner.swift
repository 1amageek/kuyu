import Foundation
import KuyuTraining

public struct LearningCampaignArtifactPruner: Sendable {
    public enum PruneError: Error, Sendable, Equatable {
        case refusingExternalCheckpointPath(String)
    }

    public init() {}

    public func pruneSeedArtifacts(
        seed: String,
        evolutionRoot: URL,
        bundle: EvolutionRunArtifactBundle,
        policy: LearningCampaignArtifactRetentionPolicy
    ) throws -> LearningCampaignArtifactRetentionRecord {
        guard policy.mode == .compact else {
            return LearningCampaignArtifactRetentionRecord(
                seed: seed,
                mode: policy.mode,
                prunedCheckpointCount: 0,
                prunedCandidateEvaluationArtifactCount: 0,
                prunedByteCount: 0,
                preservedCheckpointPaths: preservedCheckpointPaths(bundle: bundle, policy: policy)
            )
        }

        let preservedPaths = Set(preservedCheckpointPaths(bundle: bundle, policy: policy).map(normalizedPath))
        var prunedCheckpointCount = 0
        var prunedCandidateEvaluationArtifactCount = 0
        var prunedByteCount: Int64 = 0
        var seenCheckpointPaths = Set<String>()

        for candidate in bundle.candidates {
            guard let checkpointURL = candidate.checkpointURL else { continue }
            let checkpointPath = normalizedPath(checkpointURL.path)
            guard seenCheckpointPaths.insert(checkpointPath).inserted else { continue }
            guard checkpointPath.hasPrefix(normalizedPath(evolutionRoot.path)) else { continue }
            guard !preservedPaths.contains(checkpointPath) else { continue }
            prunedByteCount += byteCount(at: checkpointURL)
            if FileManager.default.fileExists(atPath: checkpointURL.path) {
                try FileManager.default.removeItem(at: checkpointURL)
                prunedCheckpointCount += 1
            }
        }

        if !policy.keepCandidateEvaluationArtifacts {
            let candidateEvaluationRoot = evolutionRoot.appendingPathComponent(
                "candidate-evaluations",
                isDirectory: true
            )
            if FileManager.default.fileExists(atPath: candidateEvaluationRoot.path) {
                prunedByteCount += byteCount(at: candidateEvaluationRoot)
                try FileManager.default.removeItem(at: candidateEvaluationRoot)
                prunedCandidateEvaluationArtifactCount += 1
            }
        }

        return LearningCampaignArtifactRetentionRecord(
            seed: seed,
            mode: policy.mode,
            prunedCheckpointCount: prunedCheckpointCount,
            prunedCandidateEvaluationArtifactCount: prunedCandidateEvaluationArtifactCount,
            prunedByteCount: prunedByteCount,
            preservedCheckpointPaths: Array(preservedPaths).sorted()
        )
    }

    private func preservedCheckpointPaths(
        bundle: EvolutionRunArtifactBundle,
        policy: LearningCampaignArtifactRetentionPolicy
    ) -> [String] {
        var paths = Set<String>()
        if policy.keepAcceptedCheckpoints,
           bundle.acceptedCheckpoint.accepted,
           let url = bundle.acceptedCheckpoint.checkpointURL {
            paths.insert(normalizedPath(url.path))
        }
        if policy.keepIncumbentCheckpoints {
            for candidate in bundle.candidates where candidate.isIncumbent == true {
                if let url = candidate.checkpointURL {
                    paths.insert(normalizedPath(url.path))
                }
            }
        }
        if policy.keepBestCandidateCheckpoints,
           let bestCandidateID = bundle.acceptedCheckpoint.bestCandidateID,
           let candidate = bundle.candidates.first(where: { $0.candidateID == bestCandidateID }),
           let url = candidate.checkpointURL {
            paths.insert(normalizedPath(url.path))
        }
        return Array(paths)
    }

    private func byteCount(at url: URL) -> Int64 {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return 0
        }
        if !isDirectory.boolValue {
            return fileByteCount(url)
        }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            total += fileByteCount(fileURL)
        }
        return total
    }

    private func fileByteCount(_ url: URL) -> Int64 {
        do {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { return 0 }
            return Int64(values.fileSize ?? 0)
        } catch {
            return 0
        }
    }

    private func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
