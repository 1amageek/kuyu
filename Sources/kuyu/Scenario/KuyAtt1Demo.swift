import Configuration
import Foundation
import Logging

public struct KuyAtt1Demo {
    public init() {}

    public func runBaseline(
        configuration: ConfigReader? = nil,
        logger: Logger? = nil,
        logDirectory: URL? = nil
    ) throws -> ValidationSummary {
        let gains = try ImuRateDampingCutGains(kp: 2.0, kd: 0.25, yawDamping: 0.2)
        let runner = try KuyAtt1Runner.baseline(gains: gains)
        let output = try runner.runWithLogs()
        let runtimeConfig = configuration.map { KuyukaiConfigLoader().load(reader: $0) }
        let activeLogger = logger ?? runtimeConfig.map { KuyukaiLoggerFactory().make(label: $0.logLabel, level: $0.logLevel) }
        let activeDirectory = logDirectory ?? runtimeConfig?.logDirectoryURL

        activeLogger?.info("KUY-ATT-1 baseline run started")

        if let directory = activeDirectory {
            let bundle = try KuyAtt1LogWriter().write(output: output, to: directory)
            activeLogger?.info("KUY-ATT-1 logs written", metadata: [
                "directory": "\(directory.path)",
                "bundle": "\(bundle.logs.count)"
            ])
        }

        activeLogger?.info("KUY-ATT-1 baseline run completed", metadata: [
            "passed": "\(output.summary.suitePassed)"
        ])

        return output.summary
    }

    public func runBaselineAndWriteLogs(to directory: URL) throws -> ScenarioLogBundle {
        let gains = try ImuRateDampingCutGains(kp: 2.0, kd: 0.25, yawDamping: 0.2)
        let runner = try KuyAtt1Runner.baseline(gains: gains)
        let output = try runner.runWithLogs()
        let writer = KuyAtt1LogWriter()
        return try writer.write(output: output, to: directory)
    }
}
