import Configuration
import Logging
import KuyuCore

public struct KuyuRuntime {
    public let config: KuyuRuntimeConfig
    public let logger: Logger

    public init(
        loader: KuyuConfigLoader = KuyuConfigLoader(),
        reader: ConfigReader? = nil
    ) {
        let config: KuyuRuntimeConfig
        if let reader {
            config = loader.load(reader: reader)
        } else {
            config = KuyuRuntimeConfig.default
        }
        let loggerFactory = KuyuLoggerFactory()
        self.config = config
        self.logger = loggerFactory.make(label: config.logLabel, level: config.logLevel)
    }

    public static func fromEnvironment() -> KuyuRuntime {
        let reader = ConfigReader(provider: EnvironmentVariablesProvider())
        return KuyuRuntime(reader: reader)
    }
}
