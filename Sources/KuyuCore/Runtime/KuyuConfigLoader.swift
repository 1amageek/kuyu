import Configuration

public struct KuyuConfigLoader {
    public init() {}

    public func load(reader: ConfigReader) -> KuyuRuntimeConfig {
        let levelString = reader.string(forKey: "KUYU_LOG_LEVEL", default: "info")
        let label = reader.string(forKey: "KUYU_LOG_LABEL", default: "kuyu")
        let logDir = reader.string(forKey: "KUYU_LOG_DIR", default: "")
        let level = KuyuRuntimeConfig.parseLogLevel(levelString)
        let directory = logDir.isEmpty ? nil : logDir
        return KuyuRuntimeConfig(logLevel: level, logLabel: label, logDirectory: directory)
    }

    public func loadFromEnvironment() -> KuyuRuntimeConfig {
        let reader = ConfigReader(provider: EnvironmentVariablesProvider())
        return load(reader: reader)
    }
}
