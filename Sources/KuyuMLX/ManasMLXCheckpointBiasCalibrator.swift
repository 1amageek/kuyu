import Foundation
import MLX

public enum ManasMLXCheckpointBiasCalibratorError: Error, Sendable, Equatable {
    case nonFiniteRawBiasDelta
    case nonEmptyOutputDirectory(String)
    case missingCheckpointFile(String)
    case missingDriveHeadBias
    case invalidDriveHeadBiasShape([Int])
}

public struct ManasMLXCheckpointBiasCalibrationSummary: Codable, Sendable, Equatable {
    public let sourceCheckpointPath: String
    public let outputCheckpointPath: String
    public let rawBiasDelta: Double

    public init(sourceCheckpointPath: String, outputCheckpointPath: String, rawBiasDelta: Double) {
        self.sourceCheckpointPath = sourceCheckpointPath
        self.outputCheckpointPath = outputCheckpointPath
        self.rawBiasDelta = rawBiasDelta
    }
}

public struct ManasMLXCheckpointBiasCalibrator: Sendable {
    public init() {}

    public func calibrate(
        sourceCheckpointURL: URL,
        outputCheckpointURL: URL,
        rawBiasDelta: Double
    ) throws -> ManasMLXCheckpointBiasCalibrationSummary {
        guard rawBiasDelta.isFinite else {
            throw ManasMLXCheckpointBiasCalibratorError.nonFiniteRawBiasDelta
        }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: outputCheckpointURL.path) {
            let contents = try fileManager.contentsOfDirectory(
                at: outputCheckpointURL,
                includingPropertiesForKeys: nil
            )
            if !contents.isEmpty {
                throw ManasMLXCheckpointBiasCalibratorError.nonEmptyOutputDirectory(outputCheckpointURL.path)
            }
        }
        try fileManager.createDirectory(at: outputCheckpointURL, withIntermediateDirectories: true)

        try copyRequiredFile(
            "model.json",
            sourceCheckpointURL: sourceCheckpointURL,
            outputCheckpointURL: outputCheckpointURL
        )
        try copyRequiredFile(
            "reflex.safetensors",
            sourceCheckpointURL: sourceCheckpointURL,
            outputCheckpointURL: outputCheckpointURL
        )

        let sourceCoreURL = sourceCheckpointURL.appendingPathComponent("core.safetensors")
        guard fileManager.fileExists(atPath: sourceCoreURL.path) else {
            throw ManasMLXCheckpointBiasCalibratorError.missingCheckpointFile(sourceCoreURL.path)
        }
        var arrays = try MLX.loadArrays(url: sourceCoreURL)
        guard let bias = arrays["driveHead.bias"] else {
            throw ManasMLXCheckpointBiasCalibratorError.missingDriveHeadBias
        }
        guard bias.shape == [1] else {
            throw ManasMLXCheckpointBiasCalibratorError.invalidDriveHeadBiasShape(bias.shape)
        }
        arrays["driveHead.bias"] = bias + MLXArray(Float(rawBiasDelta))
        try MLX.save(
            arrays: arrays,
            url: outputCheckpointURL.appendingPathComponent("core.safetensors")
        )

        return ManasMLXCheckpointBiasCalibrationSummary(
            sourceCheckpointPath: sourceCheckpointURL.path,
            outputCheckpointPath: outputCheckpointURL.path,
            rawBiasDelta: rawBiasDelta
        )
    }

    private func copyRequiredFile(
        _ fileName: String,
        sourceCheckpointURL: URL,
        outputCheckpointURL: URL
    ) throws {
        let fileManager = FileManager.default
        let sourceURL = sourceCheckpointURL.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw ManasMLXCheckpointBiasCalibratorError.missingCheckpointFile(sourceURL.path)
        }
        try fileManager.copyItem(
            at: sourceURL,
            to: outputCheckpointURL.appendingPathComponent(fileName)
        )
    }
}
