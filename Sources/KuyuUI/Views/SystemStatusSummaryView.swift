#if canImport(Metal)
import Metal
#endif
import SwiftUI

struct SystemStatusSummaryView: View {
    @Bindable var model: SimulationViewModel

    // Creating the system Metal device is expensive; never do it per body
    // evaluation.
    #if canImport(Metal)
    private static let metalDevice: (any MTLDevice)? = MTLCreateSystemDefaultDevice()
    #endif

    private static let diskRefreshInterval: Duration = .seconds(30)

    @State private var diskAvailableSummary = "--"

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
        .task(id: model.learningCampaignArtifactDirectory) {
            await refreshDiskSummaryPeriodically(
                artifactDirectory: model.learningCampaignArtifactDirectory
            )
        }
    }

    private var primaryStatus: String {
        if model.isLearningCampaignRunning {
            return "Learning"
        }
        if model.isRunning {
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
        if model.isLearningCampaignRunning || model.isRunning {
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
        if model.isLearningCampaignRunning || model.isRunning {
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
        return "idle"
    }

    private var artifactRootName: String {
        let url = URL(fileURLWithPath: model.learningCampaignArtifactDirectory)
        let name = url.lastPathComponent
        return name.isEmpty ? "--" : name
    }

    private var metalStatus: String {
        #if canImport(Metal)
        return Self.metalDevice?.name ?? "unavailable"
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

    // Disk probing walks the filesystem; it runs off the main actor on a
    // fixed interval instead of inside body evaluation.
    private func refreshDiskSummaryPeriodically(artifactDirectory: String) async {
        while !Task.isCancelled {
            let summary = await Task.detached(priority: .utility) {
                Self.diskAvailableSummary(artifactDirectory: artifactDirectory)
            }.value
            if diskAvailableSummary != summary {
                diskAvailableSummary = summary
            }
            do {
                try await Task.sleep(for: Self.diskRefreshInterval)
            } catch {
                return
            }
        }
    }

    private nonisolated static func diskAvailableSummary(artifactDirectory: String) -> String {
        let url = existingDiskProbeURL(artifactDirectory: artifactDirectory)
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

    private nonisolated static func existingDiskProbeURL(artifactDirectory: String) -> URL {
        var url = URL(fileURLWithPath: artifactDirectory)
        let fileManager = FileManager.default
        while !fileManager.fileExists(atPath: url.path), url.path != "/" {
            url.deleteLastPathComponent()
        }
        return url
    }
}
