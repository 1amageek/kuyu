import AppKit
import KuyuUI
import SwiftUI

@main
@MainActor
private enum RobotSimulatorPreviewApp {
    private static var retainedDelegate: RobotSimulatorPreviewAppDelegate?

    static func main() {
        let application = NSApplication.shared
        let delegate = RobotSimulatorPreviewAppDelegate()
        retainedDelegate = delegate
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.activate(ignoringOtherApps: true)
        application.run()
    }
}

@MainActor
private final class RobotSimulatorPreviewAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: RobotSimulatorPreviewWindowPlacement.frame(),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "RoArm M1 Dynamic Simulation"
        window.minSize = NSSize(width: 960, height: 640)
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.contentViewController = NSHostingController(rootView: RoArmM1SimulatorPreviewRootView())
        RobotSimulatorPreviewWindowPlacement.apply(to: window)
        window.orderFrontRegardless()
        self.window = window

        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
            } catch {
                return
            }
            RobotSimulatorPreviewWindowPlacement.applyToOpenWindows()
            window.orderFrontRegardless()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@MainActor
private enum RobotSimulatorPreviewWindowPlacement {
    static func frame() -> NSRect {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 820)
        let width = min(1320, max(visibleFrame.width - 80, 960))
        let height = min(860, max(visibleFrame.height - 80, 640))
        return NSRect(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.midY - height / 2,
            width: width,
            height: height
        )
    }

    static func apply(to window: NSWindow) {
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.setFrame(frame(), display: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    static func applyToOpenWindows() {
        for window in NSApplication.shared.windows {
            apply(to: window)
        }
    }
}

private struct RoArmM1SimulatorPreviewRootView: View {
    @State private var model: SimulationViewModel?
    @State private var playbackTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let model {
                NavigationStack {
                    SimulationWindowContentView(model: model)
                }
            } else {
                ProgressView("Loading RoArm M1 simulation")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            bringPreviewWindowForward()
        }
        .task {
            guard model == nil else { return }
            let previewModel = SimulationViewModel.makeRoArmM1SimulationPreviewModel()
            model = previewModel
            bringPreviewWindowForward()
            previewModel.startRoArmM1SimulationPreview()
            playbackTask?.cancel()
            playbackTask = Task {
                await previewModel.runRoArmM1SimulationPreviewPlaybackLoop()
            }
        }
        .onDisappear {
            playbackTask?.cancel()
            playbackTask = nil
        }
    }

    private func bringPreviewWindowForward() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
            } catch {
                return
            }
            RobotSimulatorPreviewWindowPlacement.applyToOpenWindows()
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}
