import Metal
import SwiftUI

public struct MonitorWindowContentView: View {
    @Bindable var model: SimulationViewModel

    public init(model: SimulationViewModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KuyuSpacing.md) {
                HStack(alignment: .top, spacing: KuyuSpacing.md) {
                    resourceSummary
                    jobQueue
                    storageSummary
                }
                consoleLogs
            }
            .padding(KuyuSpacing.md)
        }
        .navigationTitle("Monitor")
    }

    private var resourceSummary: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
                StatRow(label: "GPU", value: gpuName)
                StatRow(label: "CPU", value: "\(ProcessInfo.processInfo.activeProcessorCount) active cores")
                StatRow(label: "Memory", value: memorySummary)
                StatRow(label: "Uptime", value: uptimeSummary)
                StatRow(label: "Metal", value: MTLCreateSystemDefaultDevice() == nil ? "unavailable" : "available")
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
        MTLCreateSystemDefaultDevice()?.name ?? "unavailable"
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
