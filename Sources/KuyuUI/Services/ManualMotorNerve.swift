import Foundation
import KuyuCore
import KuyuPhysics
import KuyuScenarios

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
