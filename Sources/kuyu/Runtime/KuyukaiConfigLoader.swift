import Configuration

public struct KuyukaiConfigLoader {
    public init() {}

    public func load(reader: ConfigReader) -> KuyukaiRuntimeConfig {
        let levelString = reader.string(forKey: "KUYU_LOG_LEVEL", default: "info")
        let label = reader.string(forKey: "KUYU_LOG_LABEL", default: "kuyu")
        let logDir = reader.string(forKey: "KUYU_LOG_DIR", default: "")
        let level = KuyukaiRuntimeConfig.parseLogLevel(levelString)
        let directory = logDir.isEmpty ? nil : logDir
        return KuyukaiRuntimeConfig(logLevel: level, logLabel: label, logDirectory: directory)
    }

    public func loadFromEnvironment() -> KuyukaiRuntimeConfig {
        let reader = ConfigReader(provider: EnvironmentVariablesProvider())
        return load(reader: reader)
    }
}
