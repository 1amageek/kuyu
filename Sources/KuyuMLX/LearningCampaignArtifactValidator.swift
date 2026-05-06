import Foundation

public struct LearningCampaignArtifactValidator: Sendable {
    public enum ValidationError: Error, Sendable, Equatable {
        case invalid(LearningCampaignValidation)
    }

    public init() {}

    @discardableResult
    public func validate(
        artifactRoot: URL,
        allowFailed: Bool = false,
        allowRunning: Bool = false,
        writesValidationArtifact: Bool = true
    ) throws -> LearningCampaignValidation {
        var issues: [LearningCampaignValidationIssue] = []

        func appendIssue(_ code: String, _ detail: String) {
            issues.append(LearningCampaignValidationIssue(code: code, detail: detail))
        }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: artifactRoot.path) else {
            appendIssue("missing-artifact-root", artifactRoot.path)
            let validation = makeValidation(root: artifactRoot, issues: issues)
            if writesValidationArtifact {
                try write(validation, to: artifactRoot)
            }
            throw ValidationError.invalid(validation)
        }

        let plan: LearningCampaignPlan? = decodeJSON(
            LearningCampaignPlan.self,
            fileName: "learning-campaign-plan.json",
            root: artifactRoot,
            issues: &issues
        )
        let environment: LearningCampaignEnvironment? = decodeJSON(
            LearningCampaignEnvironment.self,
            fileName: "learning-campaign-environment.json",
            root: artifactRoot,
            issues: &issues
        )
        let statusURL = artifactRoot.appendingPathComponent("campaign-status.json")
        let status: LearningCampaignStatus?
        if allowRunning && !fileManager.fileExists(atPath: statusURL.path) {
            status = nil
        } else {
            status = decodeJSON(
                LearningCampaignStatus.self,
                fileName: "campaign-status.json",
                root: artifactRoot,
                issues: &issues
            )
        }
        let summary: LearningCampaignSummary? = decodeJSON(
            LearningCampaignSummary.self,
            fileName: "learning-campaign-summary.json",
            root: artifactRoot,
            issues: &issues
        )
        let progress = decodeJSONLines(
            LearningCampaignProgressRecord.self,
            fileName: "progress.jsonl",
            root: artifactRoot,
            issues: &issues
        )
        let resourceSampleRequired = (plan?.resourceSampleSeconds ?? 30) > 0
        let resourceSampleURL = artifactRoot.appendingPathComponent("resource-samples.jsonl")
        let resourceSamples: [LearningCampaignResourceSample]
        if resourceSampleRequired || fileManager.fileExists(atPath: resourceSampleURL.path) {
            resourceSamples = decodeJSONLines(
                LearningCampaignResourceSample.self,
                fileName: "resource-samples.jsonl",
                root: artifactRoot,
                issues: &issues
            )
        } else {
            resourceSamples = []
        }

        validate(status: status, allowFailed: allowFailed, allowRunning: allowRunning, issues: &issues)
        validate(progress: progress, allowRunning: allowRunning, issues: &issues)
        validate(resourceSamples: resourceSamples, required: resourceSampleRequired, issues: &issues)
        validate(environment: environment, issues: &issues)
        validate(plan: plan, summary: summary, root: artifactRoot, issues: &issues)

        let validation = makeValidation(root: artifactRoot, issues: issues)
        if writesValidationArtifact {
            try write(validation, to: artifactRoot)
        }
        guard validation.valid else {
            throw ValidationError.invalid(validation)
        }
        return validation
    }

    private func validate(
        status: LearningCampaignStatus?,
        allowFailed: Bool,
        allowRunning: Bool,
        issues: inout [LearningCampaignValidationIssue]
    ) {
        guard let status else { return }
        if status.status != "succeeded" && !allowFailed {
            issues.append(.init(code: "campaign-not-succeeded", detail: status.status))
        }
    }

    private func validate(
        progress: [LearningCampaignProgressRecord],
        allowRunning: Bool,
        issues: inout [LearningCampaignValidationIssue]
    ) {
        guard let last = progress.last else {
            issues.append(.init(code: "empty-progress", detail: "progress.jsonl"))
            return
        }
        if last.event != "campaign-finished" && !allowRunning {
            issues.append(.init(code: "missing-finished-progress-event", detail: "progress.jsonl"))
        }
    }

    private func validate(
        resourceSamples: [LearningCampaignResourceSample],
        required: Bool,
        issues: inout [LearningCampaignValidationIssue]
    ) {
        if resourceSamples.isEmpty {
            if required {
                issues.append(.init(code: "empty-resource-samples", detail: "resource-samples.jsonl"))
            }
            return
        }
        for (index, sample) in resourceSamples.enumerated() {
            if sample.artifactRootFreeBytes < 0 {
                issues.append(.init(
                    code: "invalid-resource-free-bytes",
                    detail: "resource-samples.jsonl:\(index + 1)"
                ))
            }
        }
    }

    private func validate(
        environment: LearningCampaignEnvironment?,
        issues: inout [LearningCampaignValidationIssue]
    ) {
        guard let environment else { return }
        if environment.repositories.isEmpty {
            issues.append(.init(
                code: "missing-repository-state",
                detail: "learning-campaign-environment.json"
            ))
        }
    }

    private func validate(
        plan: LearningCampaignPlan?,
        summary: LearningCampaignSummary?,
        root: URL,
        issues: inout [LearningCampaignValidationIssue]
    ) {
        guard let plan, let summary else { return }
        let planSeeds = plan.seeds
        let summarySeeds = summary.runs.map(\.seed)
        if planSeeds != summarySeeds {
            issues.append(.init(
                code: "seed-summary-mismatch",
                detail: "plan=\(planSeeds) summary=\(summarySeeds)"
            ))
        }
        let expectedFitnessCount = plan.population * plan.generations
        for run in summary.runs {
            let evolutionRoot = root
                .appendingPathComponent("seeds", isDirectory: true)
                .appendingPathComponent("seed-\(run.seed)", isDirectory: true)
                .appendingPathComponent("evolution", isDirectory: true)
            for fileName in [
                "accepted-checkpoint.json",
                "evolution-manifest.json",
                "evaluation-trace.jsonl",
                "fitness.jsonl",
                "candidates.jsonl"
            ] {
                let fileURL = evolutionRoot.appendingPathComponent(fileName)
                if !FileManager.default.fileExists(atPath: fileURL.path) {
                    issues.append(.init(
                        code: "missing-seed-evolution-artifact",
                        detail: "seed=\(run.seed) file=\(fileName)"
                    ))
                }
            }
            if expectedFitnessCount > 0, run.fitnessCount != expectedFitnessCount {
                issues.append(.init(
                    code: "fitness-count-mismatch",
                    detail: "seed=\(run.seed) expected=\(expectedFitnessCount) actual=\(run.fitnessCount)"
                ))
            }
            if run.accepted, run.acceptedCheckpointURL == nil {
                issues.append(.init(
                    code: "accepted-missing-checkpoint-url",
                    detail: "seed=\(run.seed)"
                ))
            }
        }
        if summary.finalCheckpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !checkpointComplete(URL(fileURLWithPath: summary.finalCheckpoint, isDirectory: true)) {
            issues.append(.init(
                code: "incomplete-final-checkpoint",
                detail: summary.finalCheckpoint
            ))
        }
    }

    private func checkpointComplete(_ url: URL) -> Bool {
        ["model.json", "core.safetensors", "reflex.safetensors"].allSatisfy { fileName in
            FileManager.default.fileExists(atPath: url.appendingPathComponent(fileName).path)
        }
    }

    private func decodeJSON<T: Decodable>(
        _ type: T.Type,
        fileName: String,
        root: URL,
        issues: inout [LearningCampaignValidationIssue]
    ) -> T? {
        let url = root.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            issues.append(.init(code: "missing-json", detail: fileName))
            return nil
        }
        do {
            return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
        } catch {
            issues.append(.init(code: "invalid-json", detail: "\(fileName): \(error)"))
            return nil
        }
    }

    private func decodeJSONLines<T: Decodable>(
        _ type: T.Type,
        fileName: String,
        root: URL,
        issues: inout [LearningCampaignValidationIssue]
    ) -> [T] {
        let url = root.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            issues.append(.init(code: "missing-jsonl", detail: fileName))
            return []
        }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            var records: [T] = []
            for (index, line) in text.split(separator: "\n").enumerated() where !line.isEmpty {
                do {
                    records.append(try JSONDecoder().decode(T.self, from: Data(line.utf8)))
                } catch {
                    issues.append(.init(
                        code: "invalid-jsonl",
                        detail: "\(fileName):\(index + 1): \(error)"
                    ))
                }
            }
            return records
        } catch {
            issues.append(.init(code: "invalid-jsonl", detail: "\(fileName): \(error)"))
            return []
        }
    }

    private func makeValidation(
        root: URL,
        issues: [LearningCampaignValidationIssue]
    ) -> LearningCampaignValidation {
        LearningCampaignValidation(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            artifactRoot: root.path,
            valid: issues.isEmpty,
            issueCount: issues.count,
            issues: issues
        )
    }

    private func write(_ validation: LearningCampaignValidation, to root: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(validation)
        let url = root.appendingPathComponent("learning-campaign-validation.json")
        try data.write(to: url, options: .atomic)
    }
}

private struct LearningCampaignEnvironment: Decodable {
    let repositories: [LearningCampaignRepositoryState]
}

private struct LearningCampaignRepositoryState: Decodable {
    let path: String
    let head: String
    let branch: String
    let dirty: Bool
}

private struct LearningCampaignProgressRecord: Decodable {
    let event: String
}

private struct LearningCampaignResourceSample: Decodable {
    let artifactRootFreeBytes: Int64
}
