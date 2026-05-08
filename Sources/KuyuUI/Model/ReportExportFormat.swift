import Foundation

enum ReportExportFormat: String, CaseIterable, Identifiable, Sendable {
    case markdown = "Markdown"
    case html = "HTML"
    case json = "JSON"
    case csv = "CSV"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .markdown:
            return "md"
        case .html:
            return "html"
        case .json:
            return "json"
        case .csv:
            return "csv"
        }
    }
}
