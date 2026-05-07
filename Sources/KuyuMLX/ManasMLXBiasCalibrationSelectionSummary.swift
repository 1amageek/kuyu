import Foundation

public struct ManasMLXBiasCalibrationCandidateSummary: Codable, Sendable, Equatable {
    public let rawBiasDelta: Double
    public let checkpointPath: String
    public let regressionArtifactRoot: String
    public let checkpointEvaluationArtifactRoot: String?
    public let accepted: Bool
    public let regressionAccepted: Bool
    public let checkpointEvaluationPassed: Bool
    public let rewardAverage: Double?
    public let taskPassRate: Double?
    public let minimumHoldTimeRatio: Double?
    public let maximumAltitudeErrorRatio: Double?
    public let reasons: [String]
    public let checkpointEvaluationReasons: [String]

    public init(
        rawBiasDelta: Double,
        checkpointPath: String,
        regressionArtifactRoot: String,
        checkpointEvaluationArtifactRoot: String?,
        accepted: Bool,
        regressionAccepted: Bool,
        checkpointEvaluationPassed: Bool,
        rewardAverage: Double?,
        taskPassRate: Double?,
        minimumHoldTimeRatio: Double?,
        maximumAltitudeErrorRatio: Double?,
        reasons: [String],
        checkpointEvaluationReasons: [String]
    ) {
        self.rawBiasDelta = rawBiasDelta
        self.checkpointPath = checkpointPath
        self.regressionArtifactRoot = regressionArtifactRoot
        self.checkpointEvaluationArtifactRoot = checkpointEvaluationArtifactRoot
        self.accepted = accepted
        self.regressionAccepted = regressionAccepted
        self.checkpointEvaluationPassed = checkpointEvaluationPassed
        self.rewardAverage = rewardAverage
        self.taskPassRate = taskPassRate
        self.minimumHoldTimeRatio = minimumHoldTimeRatio
        self.maximumAltitudeErrorRatio = maximumAltitudeErrorRatio
        self.reasons = reasons
        self.checkpointEvaluationReasons = checkpointEvaluationReasons
    }
}

public struct ManasMLXBiasCalibrationSelectionSummary: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let sourceCheckpointPath: String
    public let selectedCheckpointPath: String?
    public let selectedRawBiasDelta: Double?
    public let selectedAccepted: Bool
    public let task: String
    public let suites: [Int]
    public let episodes: Int
    public let workers: Int
    public let candidates: [ManasMLXBiasCalibrationCandidateSummary]

    public init(
        schemaVersion: Int = ManasMLXBiasCalibrationSelectionSummary.currentSchemaVersion,
        sourceCheckpointPath: String,
        selectedCheckpointPath: String?,
        selectedRawBiasDelta: Double?,
        selectedAccepted: Bool,
        task: String,
        suites: [Int],
        episodes: Int,
        workers: Int,
        candidates: [ManasMLXBiasCalibrationCandidateSummary]
    ) {
        self.schemaVersion = schemaVersion
        self.sourceCheckpointPath = sourceCheckpointPath
        self.selectedCheckpointPath = selectedCheckpointPath
        self.selectedRawBiasDelta = selectedRawBiasDelta
        self.selectedAccepted = selectedAccepted
        self.task = task
        self.suites = suites
        self.episodes = episodes
        self.workers = workers
        self.candidates = candidates
    }
}

public enum ManasMLXBiasCalibrationSelectionValidator {
    public enum ValidationError: Error, Sendable, Equatable {
        case schemaVersionMismatch(expected: Int, actual: Int)
        case emptyCandidateList
        case duplicateCandidateDelta(Double)
        case nonFiniteMetric(String)
        case acceptedFlagMismatch(delta: Double)
        case selectedCandidateMissing(String)
        case selectedCandidateRejected(String)
        case selectedAcceptedMismatch
    }

    public static func validate(_ summary: ManasMLXBiasCalibrationSelectionSummary) throws {
        guard summary.schemaVersion == ManasMLXBiasCalibrationSelectionSummary.currentSchemaVersion else {
            throw ValidationError.schemaVersionMismatch(
                expected: ManasMLXBiasCalibrationSelectionSummary.currentSchemaVersion,
                actual: summary.schemaVersion
            )
        }
        guard !summary.candidates.isEmpty else {
            throw ValidationError.emptyCandidateList
        }
        var seenDeltas = Set<Double>()
        var candidateByPath: [String: ManasMLXBiasCalibrationCandidateSummary] = [:]
        for candidate in summary.candidates {
            guard candidate.rawBiasDelta.isFinite else {
                throw ValidationError.nonFiniteMetric("rawBiasDelta")
            }
            guard seenDeltas.insert(candidate.rawBiasDelta).inserted else {
                throw ValidationError.duplicateCandidateDelta(candidate.rawBiasDelta)
            }
            try validateFinite(candidate.rewardAverage, name: "rewardAverage")
            try validateFinite(candidate.taskPassRate, name: "taskPassRate")
            try validateFinite(candidate.minimumHoldTimeRatio, name: "minimumHoldTimeRatio")
            try validateFinite(candidate.maximumAltitudeErrorRatio, name: "maximumAltitudeErrorRatio")
            guard candidate.accepted == (candidate.regressionAccepted && candidate.checkpointEvaluationPassed) else {
                throw ValidationError.acceptedFlagMismatch(delta: candidate.rawBiasDelta)
            }
            candidateByPath[candidate.checkpointPath] = candidate
        }
        if let selectedPath = summary.selectedCheckpointPath {
            guard let selectedCandidate = candidateByPath[selectedPath] else {
                throw ValidationError.selectedCandidateMissing(selectedPath)
            }
            guard selectedCandidate.accepted else {
                throw ValidationError.selectedCandidateRejected(selectedPath)
            }
            guard summary.selectedAccepted else {
                throw ValidationError.selectedAcceptedMismatch
            }
            guard summary.selectedRawBiasDelta == selectedCandidate.rawBiasDelta else {
                throw ValidationError.selectedCandidateMissing(selectedPath)
            }
        } else if summary.selectedAccepted || summary.selectedRawBiasDelta != nil {
            throw ValidationError.selectedAcceptedMismatch
        }
    }

    private static func validateFinite(_ value: Double?, name: String) throws {
        guard let value else { return }
        guard value.isFinite else {
            throw ValidationError.nonFiniteMetric(name)
        }
    }
}
