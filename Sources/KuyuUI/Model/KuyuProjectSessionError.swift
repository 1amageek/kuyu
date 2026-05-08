import Foundation

public enum KuyuProjectSessionError: Error, Sendable, Equatable, CustomStringConvertible {
    case missingSourceBundle(path: String)
    case unsupportedSourceBundleURL(String)

    public var description: String {
        switch self {
        case .missingSourceBundle(let path):
            return "Missing source model bundle: \(path)"
        case .unsupportedSourceBundleURL(let url):
            return "Unsupported source model bundle URL: \(url)"
        }
    }
}
