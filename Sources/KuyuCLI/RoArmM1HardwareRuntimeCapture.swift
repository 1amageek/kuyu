import ArgumentParser
import Foundation
import KuyuMLX
import KuyuMLXRoArmM1
import KuyuPhysics

struct CaptureRoArmM1HardwareRuntime: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "capture-roarm-m1-hardware-runtime",
        abstract: "Capture measured RoArm M1 runtime telemetry into a validated hardware runtime log."
    )

    @Option(help: "RoARM M1 robot manifest path.")
    var model: String = "Sources/KuyuUI/Resources/Models/RoArmM1/roarm-m1.kuyurobot.json"

    @Option(help: "Serial device path that emits a telemetry session header followed by newline-delimited RoArm M1 runtime sample JSON.")
    var device: String

    @Option(help: "Expected number of telemetry samples after the session header.")
    var sampleCount: Int

    @Option(help: "Output hardware runtime log JSON path.")
    var output: String

    @Option(help: "Runtime run identifier to persist in the log.")
    var runID: String

    @Option(help: "Manas bundle identifier associated with the captured runtime.")
    var bundleID: String

    @Option(name: .customLong("calibration-report"), help: "Validated hardware calibration report JSON path.")
    var calibrationReport: String

    @Option(name: .customLong("trusted-firmware-attestation-key-id"), help: "Trusted firmware attestation key identifier expected from the device acknowledgement.")
    var trustedFirmwareAttestationKeyID: String

    @Option(name: .customLong("trusted-firmware-attestation-public-key-x963"), help: "Trusted P-256 firmware attestation public key as an X9.63 hex string.")
    var trustedFirmwareAttestationPublicKeyX963: String

    @Option(name: .customLong("raw-trace-artifact"), help: "Optional saved raw Manas step trace artifact path to bind to the captured runtime report.")
    var rawTraceArtifact: String?

    @Option(name: .customLong("raw-trace-root"), help: "Artifact root that contains --raw-trace-artifact when binding saved raw trace evidence.")
    var rawTraceRoot: String?

    @Option(name: .customLong("read-timeout-seconds"), help: "Timeout for each serial byte read.")
    var readTimeoutSeconds: Double = 5.0

    @Option(name: .customLong("maximum-sample-interval-seconds"), help: "Negotiated maximum interval between measured samples.")
    var maximumSampleIntervalSeconds: Double =
        RoArmM1HardwareRuntimeCapabilityNegotiation.supported.maximumSampleIntervalSeconds

    @Option(name: .customLong("freshness-challenge-lifetime-seconds"), help: "Lifetime for the Kuyu-issued freshness challenge sent to the firmware.")
    var freshnessChallengeLifetimeSeconds: Double =
        RoArmM1HardwareRuntimeFreshnessChallengeIssuer.defaultLifetimeSeconds

    func run() async throws {
        let options = try preflightOptions()
        let loaded = try KuyuModelLoader().loadRobot(path: model)
        let calibration = try validatedCalibrationReport(path: calibrationReport, loaded: loaded)
        let capabilityNegotiation = RoArmM1HardwareRuntimeCapabilityNegotiation.supported(
            maximumSampleIntervalSeconds: options.maximumSampleIntervalSeconds
        )
        let freshnessChallenge = try RoArmM1HardwareRuntimeFreshnessChallengeIssuer().challenge(
            lifetimeSeconds: options.freshnessChallengeLifetimeSeconds
        )

        let sessionSource = RoArmM1SerialTelemetrySessionSource(
            devicePath: options.devicePath,
            expectedSampleCount: options.sampleCount,
            readTimeoutSeconds: options.readTimeoutSeconds,
            freshnessChallenge: freshnessChallenge
        )
        let publication = try await RoArmM1ArmGripperHardwareRuntimeCaptureService().capture(
            request: RoArmM1ArmGripperHardwareRuntimeCaptureRequest(
                runID: runID,
                bundleID: bundleID,
                measurementSystem: calibration.evidence.measurementSystem,
                measurementDeviceID: calibration.evidence.measurementDeviceID,
                generatedAt: Date(),
                logURL: URL(fileURLWithPath: output, isDirectory: false),
                trustedFirmwareKey: options.trustedFirmwareKey,
                capabilityNegotiation: capabilityNegotiation,
                freshnessChallenge: freshnessChallenge,
                rawTraceBinding: options.rawTraceBinding
            ),
            calibration: calibration,
            sessionSource: sessionSource
        )

        print("[roarm-m1-hardware-runtime-capture] log=\(publication.logURL.path)")
        if let telemetrySessionID = publication.log.telemetrySessionID {
            print("[roarm-m1-hardware-runtime-capture] telemetrySession=\(telemetrySessionID)")
        }
        print("[roarm-m1-hardware-runtime-capture] run=\(publication.log.runID)")
        print("[roarm-m1-hardware-runtime-capture] bundle=\(publication.log.bundleID)")
        if let freshnessChallenge = publication.log.freshnessChallenge {
            print("[roarm-m1-hardware-runtime-capture] freshnessChallenge=\(freshnessChallenge.challengeID)")
        }
        if let trustedKeyID = publication.log.trustedFirmwareAttestationKeyID {
            print("[roarm-m1-hardware-runtime-capture] trustedFirmwareAttestationKey=\(trustedKeyID)")
        }
        print("[roarm-m1-hardware-runtime-capture] calibrationReport=\(calibrationReport)")
        print("[roarm-m1-hardware-runtime-capture] measurementSystem=\(publication.log.measurementSystem)")
        print("[roarm-m1-hardware-runtime-capture] measurementDeviceID=\(publication.log.measurementDeviceID)")
        print("[roarm-m1-hardware-runtime-capture] samples=\(publication.report.sampleCount)")
        print("[roarm-m1-hardware-runtime-capture] duration=\(format(publication.report.observedDurationSeconds))")
        print("[roarm-m1-hardware-runtime-capture] maximumSampleInterval=\(format(publication.report.capabilityNegotiation.maximumSampleIntervalSeconds))")
        print("[roarm-m1-hardware-runtime-capture] maxObservedSampleInterval=\(format(publication.report.maxObservedSampleIntervalSeconds))")
        print("[roarm-m1-hardware-runtime-capture] feedback=\(publication.report.validatedFeedbackChannelCount)/\(publication.report.feedbackChannelCount)")
        print("[roarm-m1-hardware-runtime-capture] boundedRecovery=\(publication.report.boundedRecovery)")
        if let rawTraceEvidence = publication.report.rawTraceEvidence {
            print("[roarm-m1-hardware-runtime-capture] rawTrace=\(rawTraceEvidence.artifactPath)")
        }
    }

    private func preflightOptions() throws -> CaptureOptions {
        let rawTraceBinding = try resolvedRawTraceBinding()
        let trimmedDevice = device.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDevice.isEmpty else {
            throw ValidationError("--device must not be empty.")
        }
        guard sampleCount > 0 else {
            throw ValidationError("--sample-count must be greater than 0.")
        }
        guard readTimeoutSeconds.isFinite,
              readTimeoutSeconds > 0,
              readTimeoutSeconds * 1000 <= Double(Int32.max) else {
            throw ValidationError("--read-timeout-seconds must be finite and greater than 0.")
        }
        guard maximumSampleIntervalSeconds.isFinite,
              maximumSampleIntervalSeconds > 0 else {
            throw ValidationError("--maximum-sample-interval-seconds must be finite and greater than 0.")
        }
        guard freshnessChallengeLifetimeSeconds.isFinite,
              freshnessChallengeLifetimeSeconds > 0 else {
            throw ValidationError("--freshness-challenge-lifetime-seconds must be finite and greater than 0.")
        }
        let trustedFirmwareKey = try trustedFirmwareKey()
        return CaptureOptions(
            devicePath: trimmedDevice,
            sampleCount: sampleCount,
            readTimeoutSeconds: readTimeoutSeconds,
            maximumSampleIntervalSeconds: maximumSampleIntervalSeconds,
            freshnessChallengeLifetimeSeconds: freshnessChallengeLifetimeSeconds,
            trustedFirmwareKey: trustedFirmwareKey,
            rawTraceBinding: rawTraceBinding
        )
    }

    private func trustedFirmwareKey() throws -> RoArmM1HardwareRuntimeTrustedFirmwareKey {
        do {
            return try RoArmM1HardwareRuntimeTrustedFirmwareKey(
                keyID: trustedFirmwareAttestationKeyID,
                publicKeyX963: trustedFirmwareAttestationPublicKeyX963
            ).validated()
        } catch {
            throw ValidationError("--trusted-firmware-attestation-key-id and --trusted-firmware-attestation-public-key-x963 validation failed: \(error)")
        }
    }

    private func resolvedRawTraceBinding() throws -> RoArmM1HardwareRuntimeRawTraceBinding? {
        let artifactPath = rawTraceArtifact?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rootPath = rawTraceRoot?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !artifactPath.isEmpty || !rootPath.isEmpty else {
            return nil
        }
        guard !artifactPath.isEmpty else {
            throw ValidationError("--raw-trace-artifact is required when --raw-trace-root is set.")
        }
        guard !rootPath.isEmpty else {
            throw ValidationError("--raw-trace-root is required when --raw-trace-artifact is set.")
        }
        return RoArmM1HardwareRuntimeRawTraceBinding(
            rawTraceArtifactURL: URL(fileURLWithPath: artifactPath, isDirectory: false),
            artifactRoot: URL(fileURLWithPath: rootPath, isDirectory: true)
        )
    }

    private func validatedCalibrationReport(
        path: String,
        loaded: LoadedKuyuRobot
    ) throws -> RoArmM1HardwareParityReadinessService.Result {
        do {
            return try RoArmM1HardwareParityReadinessService().validateReport(
                path: path,
                body: loaded.body,
                world: loaded.world,
                embodiment: loaded.embodiment,
                compatibilityReport: loaded.compatibilityReport
            )
        } catch {
            throw ValidationError("Hardware calibration report validation failed: \(error)")
        }
    }

    private func format(_ value: Double) -> String {
        String(format: "%.6f", value)
    }
}

private struct CaptureOptions: Sendable {
    let devicePath: String
    let sampleCount: Int
    let readTimeoutSeconds: Double
    let maximumSampleIntervalSeconds: Double
    let freshnessChallengeLifetimeSeconds: Double
    let trustedFirmwareKey: RoArmM1HardwareRuntimeTrustedFirmwareKey
    let rawTraceBinding: RoArmM1HardwareRuntimeRawTraceBinding?
}
