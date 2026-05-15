import SwiftUI

#if os(macOS)
import AppKit
#endif

struct MonospacedLogLine: Identifiable, Equatable, Sendable {
    let id: String
    let text: String
}

struct MonospacedLogOutputView: View {
    let lines: [MonospacedLogLine]
    let emptyMessage: String
    var filterText: String = ""
    var noMatchesMessage: String = "No lines match the current filter."

    var body: some View {
        ZStack(alignment: .topLeading) {
            MonospacedLogTextView(lines: lines, filterText: filterText)

            if let overlayText {
                Text(overlayText)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(KuyuSpacing.sm)
                    #if os(macOS)
                    .background(Color(nsColor: .textBackgroundColor))
                    #endif
                    .allowsHitTesting(false)
            }
        }
    }

    private var overlayText: String? {
        if lines.isEmpty {
            return emptyMessage
        }
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return nil
        }
        let hasMatch = lines.contains { $0.text.localizedStandardContains(query) }
        return hasMatch ? nil : noMatchesMessage
    }
}

#if os(macOS)
struct MonospacedLogTextView: NSViewRepresentable {
    let lines: [MonospacedLogLine]
    var filterText: String = ""

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.borderType = .noBorder

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.allowsUndo = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.font = Self.defaultFont
        textView.textContainer?.lineFragmentPadding = 0
        textView.layoutManager?.allowsNonContiguousLayout = true

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        textView.defaultParagraphStyle = paragraph

        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        guard let textView = coordinator.textView, let storage = textView.textStorage else {
            return
        }

        let filter = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = visibleLines(filter: filter)
        let filterChanged = coordinator.lastFilter != filter

        if !filterChanged,
           let lastID = coordinator.lastAppendedID,
           let anchorIndex = visible.firstIndex(where: { $0.id == lastID }) {
            let newLines = visible[(anchorIndex + 1)...]
            guard !newLines.isEmpty else {
                return
            }
            let wasAtBottom = coordinator.isAtBottom()
            storage.append(Self.attributedString(for: newLines))
            coordinator.lastAppendedID = newLines.last?.id
            coordinator.trimIfNeeded(storage: storage)
            if wasAtBottom {
                coordinator.scrollToBottom()
            }
            return
        }

        let wasAtBottom = coordinator.isAtBottom() || coordinator.lastAppendedID == nil
        if visible.isEmpty {
            storage.mutableString.setString("")
        } else {
            storage.setAttributedString(Self.attributedString(for: visible[...]))
        }
        coordinator.lastAppendedID = visible.last?.id
        coordinator.lastFilter = filter
        coordinator.trimIfNeeded(storage: storage)
        if wasAtBottom {
            coordinator.scrollToBottom()
        }
    }

    private func visibleLines(filter: String) -> [MonospacedLogLine] {
        guard !filter.isEmpty else {
            return lines
        }
        return lines.filter { $0.text.localizedStandardContains(filter) }
    }

    private static let defaultFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    private static func attributedString(for lines: ArraySlice<MonospacedLogLine>) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for line in lines {
            result.append(
                NSAttributedString(
                    string: line.text + "\n",
                    attributes: [
                        .foregroundColor: lineColor(line.text),
                        .font: defaultFont
                    ]
                )
            )
        }
        return result
    }

    private static func lineColor(_ line: String) -> NSColor {
        let lowercasedPrefix = String(line.prefix(96)).lowercased()
        let lowercasedLine = line.lowercased()
        if lowercasedPrefix.contains(" error ")
            || lowercasedPrefix.contains("[error]")
            || lowercasedPrefix.contains(" critical ")
            || lowercasedPrefix.contains("[critical]")
            || lowercasedPrefix.contains(" failed")
            || lowercasedPrefix.contains(" failure")
            || lowercasedLine.contains(" validation=invalid")
        {
            return .systemRed
        }
        if lowercasedPrefix.contains(" warning ")
            || lowercasedPrefix.contains("[warning]")
            || lowercasedPrefix.contains(" reject")
        {
            return .systemYellow
        }
        if lowercasedPrefix.contains(" debug ")
            || lowercasedPrefix.contains("[debug]")
            || lowercasedPrefix.contains(" trace ")
            || lowercasedPrefix.contains("[trace]")
        {
            return .secondaryLabelColor
        }
        if lowercasedPrefix.contains(" succeeded")
            || lowercasedPrefix.contains(" completed")
            || lowercasedPrefix.contains(" accepted")
        {
            return .systemGreen
        }
        return .labelColor
    }

    final class Coordinator {
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        var lastAppendedID: String?
        var lastFilter: String = ""

        private static let softCapCharacters = 2_000_000
        private static let trimTargetCharacters = 1_500_000
        private static let bottomStickThreshold: CGFloat = 40

        @MainActor
        func isAtBottom() -> Bool {
            guard let scrollView, let documentView = scrollView.documentView else {
                return true
            }
            let visible = scrollView.contentView.bounds
            return visible.maxY >= documentView.frame.height - Self.bottomStickThreshold
        }

        @MainActor
        func scrollToBottom() {
            textView?.scrollToEndOfDocument(nil)
        }

        @MainActor
        func trimIfNeeded(storage: NSTextStorage) {
            guard storage.length > Self.softCapCharacters else {
                return
            }
            let excess = storage.length - Self.trimTargetCharacters
            let nsString = storage.string as NSString
            let searchLocation = min(excess, nsString.length)
            let paragraphRange = nsString.paragraphRange(for: NSRange(location: searchLocation, length: 0))
            let deleteLength = paragraphRange.location
            guard deleteLength > 0 else {
                return
            }
            storage.deleteCharacters(in: NSRange(location: 0, length: deleteLength))
        }
    }
}
#else
struct MonospacedLogTextView: View {
    let lines: [MonospacedLogLine]
    var filterText: String = ""

    var body: some View {
        ScrollView {
            Text(visibleText)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(KuyuSpacing.sm)
        }
    }

    private var visibleText: String {
        let filter = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = filter.isEmpty ? lines : lines.filter { $0.text.localizedStandardContains(filter) }
        return visible.map(\.text).joined(separator: "\n")
    }
}
#endif
