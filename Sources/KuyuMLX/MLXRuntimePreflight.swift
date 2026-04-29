import Foundation

public enum MLXRuntimePreflightError: Error, Equatable, CustomStringConvertible {
    case missingMetallib(String)

    public var description: String {
        switch self {
        case .missingMetallib(let path):
            return "MLX Metal library not found at \(path). Run ./scripts/install-mlx-metallib.sh release for SwiftPM release binaries, or use xcodebuild for MLX/Metal verification."
        }
    }
}

public struct MLXRuntimePreflight: Sendable {
    public init() {}

    public func check(
        metallibURL: URL? = nil,
        executablePath: String? = nil,
        fileManager: FileManager = .default
    ) throws {
        if let metallibURL {
            guard fileManager.fileExists(atPath: metallibURL.path) else {
                throw MLXRuntimePreflightError.missingMetallib(metallibURL.path)
            }
            return
        }

        let resolvedExecutablePath = executablePath
            ?? Bundle.main.executableURL?.path
            ?? CommandLine.arguments.first
        guard let resolvedExecutablePath, resolvedExecutablePath.contains("/.build/") else {
            return
        }

        let executableURL = URL(fileURLWithPath: resolvedExecutablePath)
        let candidate = executableURL.deletingLastPathComponent().appendingPathComponent("mlx.metallib")
        guard fileManager.fileExists(atPath: candidate.path) else {
            throw MLXRuntimePreflightError.missingMetallib(candidate.path)
        }
    }
}
