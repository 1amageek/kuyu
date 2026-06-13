import Metal
import SwiftUI

struct SystemWorkspaceView: View {
    @Bindable var model: SimulationViewModel

    // Creating the system Metal device is expensive; never do it per body
    // evaluation.
    private static let metalDevice: (any MTLDevice)? = MTLCreateSystemDefaultDevice()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KuyuSpacing.md) {
                HStack(alignment: .top, spacing: KuyuSpacing.md) {
                    runtimeSummary
                    resourceSummary
                }
                HStack(alignment: .top, spacing: KuyuSpacing.md) {
                    jobQueue
                    storageSummary
                }
                consoleLogs
            }
            .padding(KuyuSpacing.md)
        }
    }

    private var runtimeSummary: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                StatRow(label: "Local Runtime", value: "available")
                StatRow(label: "Metal", value: Self.metalDevice == nil ? "unavailable" : "available")
                StatRow(label: "Running Campaign", value: model.isLearningCampaignRunning ? "yes" : "no")
                StatRow(label: "Artifact Monitor", value: model.learningCampaignMonitorEnabled ? "on" : "off")
            }
        } label: {
            Label("Runtime", systemImage: "desktopcomputer")
        }
    }

    private var resourceSummary: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                StatRow(label: "GPU", value: gpuName)
                StatRow(label: "CPU", value: "\(ProcessInfo.processInfo.activeProcessorCount) active cores")
                StatRow(label: "Memory", value: memorySummary)
                StatRow(label: "Uptime", value: uptimeSummary)
            }
        } label: {
            Label("Resources", systemImage: "cpu")
        }
    }

    private var jobQueue: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                StatRow(label: "Campaign", value: model.isLearningCampaignRunning ? "running" : "idle")
                StatRow(label: "Workers", value: "\(model.learningCampaignWorkers)")
                StatRow(label: "Candidate Concurrency", value: "\(model.learningCampaignCandidateEvaluationConcurrency)")
                StatRow(label: "Progress", value: String(format: "%.0f%%", model.learningCampaignProgressFraction * 100))
            }
        } label: {
            Label("Jobs", systemImage: "tray.full")
        }
    }

    private var storageSummary: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                StatRow(label: "Artifact Root", value: URL(fileURLWithPath: model.learningCampaignArtifactDirectory).lastPathComponent)
                StatRow(label: "Models", value: "\(model.availableModels.count)")
                StatRow(label: "Runs", value: "\(model.runs.count)")
                StatRow(label: "Logs", value: "\(model.logStore.entries.count)")
            }
        } label: {
            Label("Storage", systemImage: "shippingbox")
        }
    }

    private var consoleLogs: some View {
        GroupBox {
            LogConsoleView(entries: model.logStore.entries, onClear: model.logStore.clear)
                .frame(minHeight: 260)
        } label: {
            Label("Console", systemImage: "terminal")
        }
    }

    private var gpuName: String {
        Self.metalDevice?.name ?? "unavailable"
    }

    private var memorySummary: String {
        ByteCountFormatter.string(fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory), countStyle: .memory)
    }

    private var uptimeSummary: String {
        let uptime = ProcessInfo.processInfo.systemUptime
        let hours = Int(uptime / 3600)
        let minutes = Int((uptime.truncatingRemainder(dividingBy: 3600)) / 60)
        return "\(hours)h \(minutes)m"
    }
}
