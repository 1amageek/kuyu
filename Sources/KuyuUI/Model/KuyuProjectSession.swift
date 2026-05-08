import Foundation
import KuyuTraining

public struct KuyuProjectSession: Sendable, Equatable {
    public let package: KuyuProjectPackage
    public let openedAt: Date
    public let isRunnable: Bool

    public init(package: KuyuProjectPackage, openedAt: Date, isRunnable: Bool) {
        self.package = package
        self.openedAt = openedAt
        self.isRunnable = isRunnable
    }
}
