import Configuration
import Logging

public struct KuyukaiRuntime {
    public let config: KuyukaiRuntimeConfig
    public let logger: Logger

    public init(
        loader: KuyukaiConfigLoader = KuyukaiConfigLoader(),
        reader: ConfigReader? = nil
    ) {
        let config: KuyukaiRuntimeConfig
        if let reader {
            config = loader.load(reader: reader)
        } else {
            config = KuyukaiRuntimeConfig.default
        }
        let loggerFactory = KuyukaiLoggerFactory()
        self.config = config
        self.logger = loggerFactory.make(label: config.logLabel, level: config.logLevel)
    }

    public static func fromEnvironment() -> KuyukaiRuntime {
        let reader = ConfigReader(provider: EnvironmentVariablesProvider())
        return KuyukaiRuntime(reader: reader)
    }
}
