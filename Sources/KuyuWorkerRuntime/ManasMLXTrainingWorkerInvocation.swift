import Foundation

public struct ManasMLXTrainingWorkerInvocation: Sendable, Equatable {
    public enum InvocationError: Error, Sendable, Equatable {
        case missingCommand
        case unsupportedCommand(String)
        case missingOption(String)
        case missingValue(String)
        case duplicateOption(String)
        case unknownOption(String)
        case invalidAbsolutePath(option: String, value: String)
        case invalidLaunchID(String)
    }

    public static let commandName = "run-learning-campaign-worker"

    public let launchRoot: URL
    public let launchID: UUID
    public let launchDigest: String
    public let allowedArtifactRoots: [URL]
    public let allowedSourceRoots: [URL]
    public let allowedProjectRoots: [URL]

    public init(
        launchRoot: URL,
        launchID: UUID,
        launchDigest: String,
        allowedArtifactRoots: [URL],
        allowedSourceRoots: [URL],
        allowedProjectRoots: [URL] = []
    ) throws {
        self.launchRoot = try Self.absoluteURL(
            launchRoot.path,
            option: "--launch-root"
        )
        self.launchID = launchID
        self.launchDigest = launchDigest
        self.allowedArtifactRoots = try Self.absoluteURLs(
            allowedArtifactRoots,
            option: "--allowed-artifact-root"
        )
        self.allowedSourceRoots = try Self.absoluteURLs(
            allowedSourceRoots,
            option: "--allowed-source-root"
        )
        self.allowedProjectRoots = try Self.absoluteURLs(
            allowedProjectRoots,
            option: "--allowed-project-root"
        )
    }

    public static func parse(commandLineArguments: [String]) throws -> Self {
        guard let command = commandLineArguments.first else {
            throw InvocationError.missingCommand
        }
        guard command == commandName else {
            throw InvocationError.unsupportedCommand(command)
        }

        var singletonValues: [String: String] = [:]
        var repeatedValues: [String: [String]] = [:]
        let singletonOptions = Set([
            "--launch-root",
            "--launch-id",
            "--launch-digest",
        ])
        let repeatedOptions = Set([
            "--allowed-artifact-root",
            "--allowed-source-root",
            "--allowed-project-root",
        ])
        var index = 1
        while index < commandLineArguments.count {
            let option = commandLineArguments[index]
            guard singletonOptions.contains(option) || repeatedOptions.contains(option) else {
                throw InvocationError.unknownOption(option)
            }
            let valueIndex = index + 1
            guard valueIndex < commandLineArguments.count else {
                throw InvocationError.missingValue(option)
            }
            let value = commandLineArguments[valueIndex]
            guard !value.hasPrefix("--") else {
                throw InvocationError.missingValue(option)
            }
            if singletonOptions.contains(option) {
                guard singletonValues.updateValue(value, forKey: option) == nil else {
                    throw InvocationError.duplicateOption(option)
                }
            } else {
                repeatedValues[option, default: []].append(value)
            }
            index += 2
        }

        let launchRootPath = try requiredValue("--launch-root", in: singletonValues)
        let launchIDValue = try requiredValue("--launch-id", in: singletonValues)
        let launchDigest = try requiredValue("--launch-digest", in: singletonValues)
        guard let launchID = UUID(uuidString: launchIDValue) else {
            throw InvocationError.invalidLaunchID(launchIDValue)
        }
        return try Self(
            launchRoot: absoluteURL(launchRootPath, option: "--launch-root"),
            launchID: launchID,
            launchDigest: launchDigest,
            allowedArtifactRoots: try requiredURLs(
                "--allowed-artifact-root",
                in: repeatedValues
            ),
            allowedSourceRoots: try requiredURLs(
                "--allowed-source-root",
                in: repeatedValues
            ),
            allowedProjectRoots: try urls(
                "--allowed-project-root",
                in: repeatedValues
            )
        )
    }

    private static func requiredValue(
        _ option: String,
        in values: [String: String]
    ) throws -> String {
        guard let value = values[option] else {
            throw InvocationError.missingOption(option)
        }
        return value
    }

    private static func requiredURLs(
        _ option: String,
        in values: [String: [String]]
    ) throws -> [URL] {
        let urls = try urls(option, in: values)
        guard !urls.isEmpty else {
            throw InvocationError.missingOption(option)
        }
        return urls
    }

    private static func urls(
        _ option: String,
        in values: [String: [String]]
    ) throws -> [URL] {
        try (values[option] ?? []).map { value in
            try absoluteURL(value, option: option)
        }
    }

    private static func absoluteURLs(
        _ values: [URL],
        option: String
    ) throws -> [URL] {
        try values.map { try absoluteURL($0.path, option: option) }
    }

    private static func absoluteURL(_ value: String, option: String) throws -> URL {
        guard value.hasPrefix("/") else {
            throw InvocationError.invalidAbsolutePath(option: option, value: value)
        }
        return URL(fileURLWithPath: value, isDirectory: true).standardizedFileURL
    }
}
