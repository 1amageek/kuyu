import AppKit
import KuyuTraining
import KuyuUI
import SwiftUI

@main
@MainActor
private enum TrainingInspectionPreviewApp {
    private static var retainedDelegate: TrainingInspectionPreviewAppDelegate?

    static func main() {
        let application = NSApplication.shared
        let delegate = TrainingInspectionPreviewAppDelegate()
        retainedDelegate = delegate
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.activate(ignoringOtherApps: true)
        application.run()
    }
}

@MainActor
private final class TrainingInspectionPreviewAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: previewFrame(),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = isLearningCampaignActivityPreview
            ? "Kuyu Learning Campaign Activity"
            : "Kuyu Training Inspection"
        window.minSize = isLearningCampaignActivityPreview
            ? NSSize(width: 520, height: 640)
            : NSSize(width: 1100, height: 720)
        window.contentViewController = NSHostingController(rootView: rootView())
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func rootView() -> AnyView {
        guard let argument = CommandLine.arguments.dropFirst().first else {
            return AnyView(ContentUnavailableView(
                "Inspection Artifact Required",
                systemImage: "doc.badge.ellipsis",
                description: Text("Pass a validated training-inspection.json path.")
            ))
        }
        if argument == "--learning-campaign-activity" {
            return KuyuUIPreviewFactory.learningCampaignActivityView()
        }
        do {
            let artifact = try TrainingRunInspectionArtifactStore().validatedArtifact(
                at: URL(fileURLWithPath: argument, isDirectory: false)
            )
            return AnyView(
                TrainingRunInspectionView(artifact: artifact)
                    .padding(12)
            )
        } catch {
            return AnyView(ContentUnavailableView(
                "Inspection Artifact Invalid",
                systemImage: "exclamationmark.triangle",
                description: Text(String(describing: error))
            ))
        }
    }

    private func previewFrame() -> NSRect {
        let visible = NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let minimumWidth: CGFloat = isLearningCampaignActivityPreview ? 720 : 1100
        let maximumWidth: CGFloat = isLearningCampaignActivityPreview ? 820 : 1500
        let width = min(maximumWidth, max(visible.width - 60, minimumWidth))
        let height = min(960, max(visible.height - 60, 720))
        return NSRect(
            x: visible.midX - width / 2,
            y: visible.midY - height / 2,
            width: width,
            height: height
        )
    }

    private var isLearningCampaignActivityPreview: Bool {
        CommandLine.arguments.dropFirst().first == "--learning-campaign-activity"
    }
}
