import SwiftUI

#if os(macOS)
import AppKit
#endif

struct CopyableTextBlockView: View {
    let title: String?
    let text: String
    let emptyText: String
    let previewLineLimit: Int
    let previewCharacterLimit: Int

    init(
        title: String? = nil,
        text: String,
        emptyText: String = "--",
        previewLineLimit: Int = 24,
        previewCharacterLimit: Int = 4_000
    ) {
        self.title = title
        self.text = text
        self.emptyText = emptyText
        self.previewLineLimit = previewLineLimit
        self.previewCharacterLimit = previewCharacterLimit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
            HStack {
                if let title {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Copy") {
                    copyToPasteboard(displayText)
                }
                .disabled(displayText.isEmpty)
                .controlSize(.small)
            }
            Text(displayText.isEmpty ? emptyText : previewText)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(displayText.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(previewLineLimit + 2)
                .textSelection(.enabled)
        }
    }

    private var displayText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var previewText: String {
        guard !displayText.isEmpty else { return "" }
        let lines = displayText.split(separator: "\n", omittingEmptySubsequences: false)
        let selectedLines = lines.prefix(max(1, previewLineLimit)).joined(separator: "\n")
        let characterLimited = String(selectedLines.prefix(max(1, previewCharacterLimit)))
        let omittedLineCount = max(0, lines.count - previewLineLimit)
        let omittedCharacterCount = max(0, displayText.count - characterLimited.count)
        guard omittedLineCount > 0 || omittedCharacterCount > 0 else {
            return characterLimited
        }
        return characterLimited + "\n... truncated preview; copy for full text (\(omittedLineCount) more lines, \(omittedCharacterCount) more characters)"
    }

    private func copyToPasteboard(_ value: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #endif
    }
}
