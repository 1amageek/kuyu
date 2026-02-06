import Foundation
import KuyuCore
import KuyuProfiles

public final class ManualActuatorStore {
    private let lock = NSLock()
    private var values: [Double]
    private var channelCount: Int
    private var enabled: Bool

    public init(values: [Double] = [0.0, 0.0, 0.0, 0.0], channelCount: Int = 4, isEnabled: Bool = false) {
        let normalizedCount = max(channelCount, 1)
        self.channelCount = normalizedCount
        self.values = ManualActuatorStore.normalize(values, channelCount: normalizedCount)
        self.enabled = isEnabled
    }

    var isEnabled: Bool {
        get { withLock { enabled } }
        set { withLock { enabled = newValue } }
    }

    func update(values: [Double]) {
        withLock {
            self.values = ManualActuatorStore.normalize(values, channelCount: channelCount)
        }
    }

    func configure(channelCount: Int) {
        let normalizedCount = max(channelCount, 1)
        withLock {
            guard normalizedCount != self.channelCount else { return }
            self.channelCount = normalizedCount
            self.values = ManualActuatorStore.normalize(self.values, channelCount: normalizedCount)
        }
    }

    func currentValues() -> [Double] {
        withLock { values }
    }

    func currentActuatorValues() -> [ActuatorValue] {
        let snapshot = withLock { (values: values, channelCount: channelCount) }
        var outputs: [ActuatorValue] = []
        outputs.reserveCapacity(snapshot.channelCount)
        for index in 0..<snapshot.channelCount {
            let value = index < snapshot.values.count ? snapshot.values[index] : 0.0
            let clamped = ManualActuatorStore.clamp(value)
            let actuatorIndex = ActuatorIndex(UInt32(index))
            do {
                let output = try ActuatorValue(index: actuatorIndex, value: clamped)
                outputs.append(output)
            } catch {
                assertionFailure("Invalid manual actuator value: \(error)")
            }
        }
        return outputs
    }

    private static func normalize(_ values: [Double], channelCount: Int) -> [Double] {
        (0..<max(channelCount, 1)).map { idx in
            let value = idx < values.count ? values[idx] : 0.0
            return clamp(value)
        }
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0.0), 1.0)
    }

    @discardableResult
    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

public struct ManualMotorNerve: MotorNerveEndpoint {
    private let store: ManualActuatorStore
    private let channelMaxima: [Double]

    public init(store: ManualActuatorStore, channelMaxima: [Double]) {
        self.store = store
        self.channelMaxima = channelMaxima.map { max($0, 0.0) }
        self.store.configure(channelCount: self.channelMaxima.count)
    }

    public init(store: ManualActuatorStore, motorMaxThrusts: MotorMaxThrusts) {
        self.init(
            store: store,
            channelMaxima: [
                motorMaxThrusts.f1,
                motorMaxThrusts.f2,
                motorMaxThrusts.f3,
                motorMaxThrusts.f4
            ]
        )
    }

    public mutating func update(
        input drives: [DriveIntent],
        corrections: [ReflexCorrection],
        telemetry: MotorNerveTelemetry,
        time: WorldTime
    ) throws -> [ActuatorValue] {
        _ = drives
        _ = corrections
        _ = telemetry
        _ = time
        let values = store.currentValues()
        let count = min(values.count, channelMaxima.count)
        var outputs: [ActuatorValue] = []
        outputs.reserveCapacity(count)
        for index in 0..<count {
            let value = values[index] * channelMaxima[index]
            let actuatorIndex = ActuatorIndex(UInt32(index))
            let output = try ActuatorValue(index: actuatorIndex, value: value)
            outputs.append(output)
        }
        return outputs
    }
}
