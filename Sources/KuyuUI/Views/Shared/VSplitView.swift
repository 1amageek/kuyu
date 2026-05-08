import AppKit
import SwiftUI

/// A drop-in replacement for SwiftUI's `VSplitView` backed by `NSSplitView`.
///
/// SwiftUI's `VSplitView` has a bug where `frame(maxWidth:)` on child views
/// prevents the split view from shrinking. This wrapper uses `NSSplitView`
/// directly, which does not have that issue.
struct VSplitView<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Group(subviews: content) { subviews in
            VSplitViewRepresentable(subviews: subviews.map { AnyView($0) })
        }
    }
}

private struct VSplitViewRepresentable: NSViewRepresentable {
    let subviews: [AnyView]

    func makeNSView(context: Context) -> NSSplitView {
        let splitView = NSSplitView()
        splitView.isVertical = false
        splitView.dividerStyle = .thin
        splitView.delegate = context.coordinator
        rebuildSubviews(splitView)
        return splitView
    }

    func updateNSView(_ splitView: NSSplitView, context: Context) {
        let existing = splitView.arrangedSubviews
        if existing.count == subviews.count {
            for (index, view) in subviews.enumerated() {
                if let host = existing[index] as? NSHostingView<AnyView> {
                    host.rootView = view
                }
            }
        } else {
            rebuildSubviews(splitView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func rebuildSubviews(_ splitView: NSSplitView) {
        let oldHeights = splitView.arrangedSubviews.map(\.frame.height)
        let totalOldHeight = oldHeights.reduce(0, +)

        for view in splitView.arrangedSubviews.reversed() {
            view.removeFromSuperview()
        }
        for (index, view) in subviews.enumerated() {
            let host = NSHostingView(rootView: view)
            host.translatesAutoresizingMaskIntoConstraints = false
            splitView.addArrangedSubview(host)

            // First pane resizes freely; later panes keep their size.
            if index == 0 {
                splitView.setHoldingPriority(.defaultLow, forSubviewAt: index)
            } else {
                splitView.setHoldingPriority(.defaultHigh, forSubviewAt: index)
            }
        }

        if totalOldHeight > 0, oldHeights.count == subviews.count {
            for (index, height) in oldHeights.enumerated() where index < splitView.arrangedSubviews.count {
                let view = splitView.arrangedSubviews[index]
                var frame = view.frame
                frame.size.height = height
                view.frame = frame
            }
            splitView.adjustSubviews()
        }
    }

    final class Coordinator: NSObject, NSSplitViewDelegate {
        func splitView(
            _ splitView: NSSplitView,
            constrainMinCoordinate proposedMinimumPosition: CGFloat,
            ofSubviewAt dividerIndex: Int
        ) -> CGFloat {
            return max(proposedMinimumPosition, 200)
        }

        func splitView(
            _ splitView: NSSplitView,
            constrainMaxCoordinate proposedMaximumPosition: CGFloat,
            ofSubviewAt dividerIndex: Int
        ) -> CGFloat {
            return min(proposedMaximumPosition, splitView.bounds.height - 80)
        }

        func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
            false
        }

        func splitView(
            _ splitView: NSSplitView,
            additionalEffectiveRectOfDividerAt dividerIndex: Int
        ) -> NSRect {
            guard splitView.arrangedSubviews.count > dividerIndex + 1 else {
                return .zero
            }
            let bottomPane = splitView.arrangedSubviews[dividerIndex + 1]
            let paneFrame = bottomPane.frame
            let dragStripHeight: CGFloat = 8
            return NSRect(
                x: paneFrame.origin.x,
                y: paneFrame.origin.y,
                width: paneFrame.width,
                height: dragStripHeight
            )
        }
    }
}
