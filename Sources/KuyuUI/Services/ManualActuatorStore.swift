import Foundation
import Synchronization

/// Thread-safe store for manual actuator slider values shared between the UI
/// and the simulation thread.
public final class ManualActuatorStore: Sendable {
    private struct State: Sendable {
        var values: [Double]
        var channelCount: Int
        var enabled: Bool
    }

    private let state: Mutex<State>

    public init(values: [Double] = [0.0, 0.0, 0.0, 0.0], channelCount: Int = 4, isEnabled: Bool = false) {
        let normalizedCount = max(channelCount, 1)
        self.state = Mutex(
            State(
                values: ManualActuatorStore.normalize(values, channelCount: normalizedCount),
                channelCount: normalizedCount,
                enabled: isEnabled
            )
        )
    }

    var isEnabled: Bool {
        get { state.withLock { $0.enabled } }
        set { state.withLock { $0.enabled = newValue } }
    }

    func update(values: [Double]) {
        state.withLock {
            $0.values = ManualActuatorStore.normalize(values, channelCount: $0.channelCount)
        }
    }

    func configure(channelCount: Int) {
        let normalizedCount = max(channelCount, 1)
        state.withLock {
            guard normalizedCount != $0.channelCount else { return }
            $0.channelCount = normalizedCount
            $0.values = ManualActuatorStore.normalize($0.values, channelCount: normalizedCount)
        }
    }

    func currentValues() -> [Double] {
        state.withLock { $0.values }
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
}
