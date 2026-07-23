import Foundation

@MainActor
struct TransactionalDirectoryPublisher {
    enum PublicationError: Error, Sendable, Equatable {
        case cleanupFailed(primary: String, cleanup: String)
    }

    func publish(
        to destinationURL: URL,
        operation: @MainActor (URL) async throws -> Void
    ) async throws {
        let fileManager = FileManager.default
        let parentURL = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)

        let stagingURL = makeStagingURL(for: destinationURL)
        do {
            try await operation(stagingURL)
            try Task.checkCancellation()
            if fileManager.fileExists(atPath: destinationURL.path) {
                _ = try fileManager.replaceItemAt(destinationURL, withItemAt: stagingURL)
            } else {
                try fileManager.moveItem(at: stagingURL, to: destinationURL)
            }
        } catch {
            let primaryError = error
            if fileManager.fileExists(atPath: stagingURL.path) {
                do {
                    try fileManager.removeItem(at: stagingURL)
                } catch {
                    throw PublicationError.cleanupFailed(
                        primary: String(describing: primaryError),
                        cleanup: String(describing: error)
                    )
                }
            }
            throw primaryError
        }
    }

    private func makeStagingURL(for destinationURL: URL) -> URL {
        let pathExtension = destinationURL.pathExtension
        let baseName = destinationURL.deletingPathExtension().lastPathComponent
        var stagingURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(
                ".\(baseName)-staging-\(UUID().uuidString)",
                isDirectory: true
            )
        if !pathExtension.isEmpty {
            stagingURL.appendPathExtension(pathExtension)
        }
        return stagingURL
    }
}
