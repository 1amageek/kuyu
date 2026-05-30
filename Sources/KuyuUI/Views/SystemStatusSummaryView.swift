#if canImport(Metal)
import Metal
#endif
import SwiftUI

struct SystemStatusSummaryView: View {
    @Bindable var model: SimulationViewModel

    var body: some View {
        GroupBox("System Status") {
            VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
                Label(primaryStatus, systemImage: primarySystemImage)
                    .foregroundStyle(primaryColor)
                LabeledContent("Run", value: runStatus)
                LabeledContent("Readiness", value: model.learningCampaignReadiness.status.label)
                LabeledContent("Monitor", value: model.learningCampaignMonitorEnabled ? "watching" : "off")
                LabeledContent("Artifacts", value: artifactRootName)
                Divider()
                LabeledContent("Metal", value: metalStatus)
                LabeledContent("Memory", value: memorySummary)
                LabeledContent("Disk", value: diskAvailableSummary)
                LabeledContent("Logs", value: "\(model.logStore.entries.count)")
            }
            .font(.caption)
        }
        .controlSize(.small)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("System Status")
    }

    private var primaryStatus: String {
        if model.isLearningCampaignRunning {
            return "Learning"
        }
        if model.isRunning || model.isLoopRunning || model.isTraining {
            return "Job running"
        }
        switch model.learningCampaignReadiness.status {
        case .blocked:
            return "Preflight required"
        case .ready:
            return "Ready"
        case .idle:
            return "Idle"
        }
    }

    private var primarySystemImage: String {
        if model.isLearningCampaignRunning || model.isRunning || model.isLoopRunning || model.isTraining {
            return "play.circle.fill"
        }
        switch model.learningCampaignReadiness.status {
        case .blocked:
            return "exclamationmark.triangle.fill"
        case .ready:
            return "checkmark.circle.fill"
        case .idle:
            return "circle"
        }
    }

    private var primaryColor: Color {
        if model.isLearningCampaignRunning || model.isRunning || model.isLoopRunning || model.isTraining {
            return .green
        }
        switch model.learningCampaignReadiness.status {
        case .blocked:
            return .orange
        case .ready:
            return .green
        case .idle:
            return .secondary
        }
    }

    private var runStatus: String {
        if model.isLearningCampaignRunning {
            return model.learningCampaignCurrentPhase
        }
        if model.isRunning {
            return "simulation"
        }
        if model.isLoopRunning || model.isTraining {
            return "training"
        }
        return "idle"
    }

    private var artifactRootName: String {
        let url = URL(fileURLWithPath: model.learningCampaignArtifactDirectory)
        let name = url.lastPathComponent
        return name.isEmpty ? "--" : name
    }

    private var metalStatus: String {
        #if canImport(Metal)
        return MTLCreateSystemDefaultDevice()?.name ?? "unavailable"
        #else
        return "unavailable"
        #endif
    }

    private var memorySummary: String {
        ByteCountFormatter.string(
            fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory),
            countStyle: .memory
        )
    }

    private var diskAvailableSummary: String {
        let url = existingDiskProbeURL()
        do {
            let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            guard let capacity = values.volumeAvailableCapacityForImportantUsage else {
                return "--"
            }
            return ByteCountFormatter.string(fromByteCount: capacity, countStyle: .file)
        } catch {
            return "unavailable"
        }
    }

    private func existingDiskProbeURL() -> URL {
        var url = URL(fileURLWithPath: model.learningCampaignArtifactDirectory)
        let fileManager = FileManager.default
        while !fileManager.fileExists(atPath: url.path), url.path != "/" {
            url.deleteLastPathComponent()
        }
        return url
    }
}
